import { store, saveState } from './state.js';
import { CHART_COLORS, MAX_HIST_ASSETS, HIST_PAGE_SIZES, HIST_DEFAULT_PAGE } from './constants.js';
import { fillHiddenSelectAndMenu, syncDropdownLabel, wireCoSelectDropdown, wireCoSelectTypeahead } from './dropdowns.js';
import { fetchWithRetry, withButtonSpinner } from './api.js';
import { chartTheme } from './theme.js';
import { showToast } from './toasts.js';
import {
  escapeHtml, formatPrice, formatPct, trendClass, pairKey,
  displayName, displayIcon, parsePairKeyString,
  parseTimestamp, formatLocalDateTime, formatChartAxisLabel,
  pad2, destroyChartInstance
} from './formatting.js';

/* ---- Module-local state ---- */
let histAllItems      = [];
let histShown         = 0;
let histMultiMode     = false;
let histAbsoluteValues = {};
let histMainChart     = null;

/* ---- Gap markers ---- */
function insertGapMarkers(items) {
  if (!items || items.length < 2) return items;
  const timestamps = items.map(function (it) {
    const d = parseTimestamp(it.created_at);
    return d ? d.getTime() : 0;
  });
  const diffs = [];
  for (let i = 1; i < timestamps.length; i++) {
    const diff = timestamps[i] - timestamps[i - 1];
    if (diff > 0) diffs.push(diff);
  }
  if (!diffs.length) return items;
  diffs.sort(function (a, b) { return a - b; });
  const median = diffs[Math.floor(diffs.length / 2)];
  let threshold = median * 3;
  const minGap = 30 * 60 * 1000;
  if (threshold < minGap) threshold = minGap;
  const result = [items[0]];
  for (let j = 1; j < items.length; j++) {
    const gap = timestamps[j] - timestamps[j - 1];
    if (gap > threshold) {
      result.push({
        created_at: items[j - 1].created_at,
        price_uah: null, price_usd: null,
        pct_change_from_prev: null, _gap: true
      });
    }
    result.push(items[j]);
  }
  return result;
}

/* ---- Downsampling ---- */
function downsampleItems(items, bucketMs, minTs, maxTs) {
  if (!items || items.length === 0 || !bucketMs) return items;
  
  const sortedItems = items.slice().sort(function(a, b) {
    const da = parseTimestamp(a.created_at);
    const db = parseTimestamp(b.created_at);
    return (da ? da.getTime() : 0) - (db ? db.getTime() : 0);
  });

  // Determine actual bounds
  const firstDataTs = parseTimestamp(sortedItems[0].created_at).getTime();
  const lastDataTs  = parseTimestamp(sortedItems[sortedItems.length - 1].created_at).getTime();
  
  const startTs = (minTs != null) ? Math.floor(minTs / bucketMs) * bucketMs : Math.floor(firstDataTs / bucketMs) * bucketMs;
  const endTs   = (maxTs != null) ? Math.floor(maxTs / bucketMs) * bucketMs : Math.floor(lastDataTs / bucketMs) * bucketMs;

  const buckets = {};
  sortedItems.forEach(function(it) {
    const ts = parseTimestamp(it.created_at).getTime();
    const bStart = Math.floor(ts / bucketMs) * bucketMs;
    // Keep the latest item in the bucket
    buckets[bStart] = it;
  });

  const result = [];
  for (let t = startTs; t <= endTs; t += bucketMs) {
    if (buckets[t]) {
      var snapped = Object.assign({}, buckets[t]);
      snapped.created_at = new Date(t).toISOString();
      result.push(snapped);
    } else {
      var gapDate = new Date(t).toISOString();
      result.push({
        created_at: gapDate,
        price_uah: null, price_usd: null,
        pct_change_from_prev: null, _gap: true
      });
    }
  }
  
  return result;
}

/* ---- Asset select helpers ---- */
export function getSelectedHistAssets() {
  const { el } = store;
  if (!el.histAsset) return [];
  const selected = [];
  Array.prototype.forEach.call(el.histAsset.options, function (o) {
    if (o.selected) selected.push(o.value);
  });
  return selected;
}

export function updateHistAssetLabel() {
  const sel = getSelectedHistAssets();
  const { el } = store;
  if (!el.histAssetLabel) return;
  if (sel.length === 0) {
    el.histAssetLabel.textContent = '—';
  } else if (sel.length === 1) {
    const p = parsePairKeyString(sel[0]);
    el.histAssetLabel.textContent = p ? p.sym : sel[0];
  } else {
    el.histAssetLabel.textContent = sel.length + ' активів обрано';
  }
}

export function syncHistAssetCheckboxes() {
  const { el } = store;
  const sel = new Set(getSelectedHistAssets());
  el.histAssetMenu.querySelectorAll('input[data-cb-value]').forEach(function (cb) {
    cb.checked = sel.has(cb.getAttribute('data-cb-value'));
  });
}

export function fillHistAssetSelect() {
  const { el, st } = store;
  if (!el.histAsset || !el.histAssetMenu) return;
  const prevSelected = getSelectedHistAssets();
  el.histAsset.innerHTML    = '';
  el.histAssetMenu.innerHTML = '';

  const searchLi    = document.createElement('li');
  searchLi.className = 'px-2 pb-2 hist-asset-search-wrap';
  const searchInput = document.createElement('input');
  searchInput.type        = 'text';
  searchInput.className   = 'form-control form-control-sm';
  searchInput.placeholder = 'Пошук активу\u2026';
  searchInput.setAttribute('aria-label', 'Пошук активу');
  searchLi.appendChild(searchInput);
  el.histAssetMenu.appendChild(searchLi);

  searchInput.addEventListener('input', function () {
    const q = this.value.toLowerCase().trim();
    el.histAssetMenu.querySelectorAll('li[data-asset-item]').forEach(function (li) {
      const label = (li.getAttribute('data-search-label') || '').toLowerCase();
      li.style.display = label.indexOf(q) >= 0 ? '' : 'none';
    });
  });
  searchInput.addEventListener('click',   function (ev) { ev.stopPropagation(); });
  searchInput.addEventListener('keydown', function (ev) { ev.stopPropagation(); });

  store.liveRates.forEach(function (r) {
    const value = (r.asset_symbol || '').toUpperCase() + ':' + r.asset_type;
    const symU  = (r.asset_symbol || '').toUpperCase();
    const label = symU + ' \u2014 ' + displayName(r) + '  ' + displayIcon(r);
    el.histAsset.appendChild(new Option(label, value));

    const li = document.createElement('li');
    li.setAttribute('data-asset-item', '1');
    li.setAttribute('data-search-label', symU + ' ' + displayName(r));
    const btn = document.createElement('button');
    btn.type      = 'button';
    btn.className = 'dropdown-item text-start py-2 d-flex align-items-center gap-2';
    btn.setAttribute('data-value', value);
    const cb = document.createElement('input');
    cb.type      = 'checkbox';
    cb.className = 'form-check-input me-0';
    cb.style.pointerEvents = 'none';
    cb.setAttribute('data-cb-value', value);
    btn.appendChild(cb);
    btn.appendChild(document.createTextNode(label));
    li.appendChild(btn);
    el.histAssetMenu.appendChild(li);
  });

  const prefer = st.histDefaultPair;
  if (prevSelected.length) {
    prevSelected.forEach(function (v) {
      const o = el.histAsset.querySelector('option[value="' + v + '"]');
      if (o) o.selected = true;
    });
  } else if (prefer && typeof prefer === 'string') {
    const arr = prefer.indexOf(',') >= 0 ? prefer.split(',') : [prefer];
    arr.forEach(function (v) {
      const o = el.histAsset.querySelector('option[value="' + v.trim() + '"]');
      if (o) o.selected = true;
    });
  }
  if (!getSelectedHistAssets().length && el.histAsset.options.length) {
    el.histAsset.options[0].selected = true;
  }
  syncHistAssetCheckboxes();
  updateHistAssetLabel();
}

export function wireHistAssetMultiSelect() {
  const { el } = store;
  if (!el.histAssetMenu || !el.histAsset) return;
  el.histAssetMenu.addEventListener('click', function (ev) {
    const item = ev.target.closest('button[data-value]');
    if (!item || !el.histAssetMenu.contains(item)) return;
    ev.preventDefault();
    ev.stopPropagation();
    const val = item.getAttribute('data-value');
    const opt = el.histAsset.querySelector('option[value="' + val + '"]');
    if (!opt) return;
    if (opt.selected) {
      opt.selected = false;
    } else {
      if (getSelectedHistAssets().length >= MAX_HIST_ASSETS) {
        showToast('Максимум ' + MAX_HIST_ASSETS + ' активів одночасно', 'warning');
        return;
      }
      opt.selected = true;
    }
    syncHistAssetCheckboxes();
    updateHistAssetLabel();
    const selected = getSelectedHistAssets();
    store.st.histDefaultPair = selected.join(',');
    saveState({ histDefaultPair: store.st.histDefaultPair });
  });
}

/* ---- Custom date range visibility ---- */
export function toggleCustomRangeFields() {
  const wrap = document.getElementById('hist-custom-range-wrap');
  if (!wrap) return;
  wrap.classList.toggle('d-none', store.el.histRange.value !== 'custom');
}

/* ---- Filter inits ---- */
export function initHistRangeFilter() {
  const { el } = store;
  if (!el.histRange || !el.histRangeMenu || !el.histRangeLabel) return;
  const defs = [
    { value: '12h',    label: '12 годин' },
    { value: '24h',    label: '24 години' },
    { value: '7d',     label: '7 днів' },
    { value: '30d',    label: '1 місяць' },
    { value: 'all',    label: 'Увесь час' },
    { value: 'custom', label: 'Свій діапазон' }
  ];
  fillHiddenSelectAndMenu(el.histRange, el.histRangeMenu, defs);
  const saved   = store.st.histRange || '7d';
  const allowed = new Set(defs.map(function (d) { return d.value; }));
  el.histRange.value = allowed.has(saved) ? saved : '7d';
  syncDropdownLabel(el.histRange, el.histRangeLabel);
  toggleCustomRangeFields();
}

export function initHistPageSizeFilter() {
  const { el } = store;
  if (!el.histPageSize || !el.histPageSizeMenu || !el.histPageSizeLabel) return;
  const defs = HIST_PAGE_SIZES.map(function (n) { return { value: String(n), label: String(n) }; });
  fillHiddenSelectAndMenu(el.histPageSize, el.histPageSizeMenu, defs);
  el.histPageSize.value = String(store.st.histPageSize || HIST_DEFAULT_PAGE);
  syncDropdownLabel(el.histPageSize, el.histPageSizeLabel);
}

/* ---- Table rendering ---- */
function getHistPageSize() {
  return Number(store.st.histPageSize) || HIST_DEFAULT_PAGE;
}

function buildHistoryTableRowsHtml(items, showAssetCol) {
  return items.map(function (it) {
    if (it._gap) return '';
    const pct     = it.pct_change_from_prev;
    const pctCell = pct == null ? '—' : formatPct(pct);
    const dtEsc   = escapeHtml(formatLocalDateTime(it.created_at));
    const uahEsc  = escapeHtml(formatPrice(it.price_uah));
    const usdEsc  = escapeHtml(formatPrice(it.price_usd));
    const pctEsc  = escapeHtml(pctCell);
    const tc      = trendClass(pct);
    const symCell = showAssetCol ? '<td><strong>' + escapeHtml(it._sym || '') + '</strong></td>' : '';
    return (
      '<tr>' + symCell + '<td>' + dtEsc + '</td>' +
      '<td class="text-end">' + uahEsc + '</td>' +
      '<td class="text-end">' + usdEsc + '</td>' +
      '<td class="text-end ' + tc + '">' + pctEsc + '</td></tr>'
    );
  }).join('');
}

export function renderHistoryTable() {
  const { el } = store;
  if (!el.histTbody) return;
  const showAssetCol = histMultiMode;
  let realItems = histAllItems.filter(function (it) { return !it._gap; });
  if (!histMultiMode) realItems = realItems.slice().reverse();
  const pageSize = getHistPageSize();
  const slice = realItems.slice(0, histShown + pageSize);
  el.histTbody.innerHTML = buildHistoryTableRowsHtml(slice, showAssetCol);
  histShown = slice.length;

  const table = el.histTbody.closest('table');
  if (table) {
    const existingAssetTh = table.querySelector('th[data-hist-asset-col]');
    const firstTh         = table.querySelector('thead tr th');
    if (showAssetCol && !existingAssetTh && firstTh) {
      const th = document.createElement('th');
      th.setAttribute('scope', 'col');
      th.setAttribute('data-hist-asset-col', '1');
      th.textContent = 'Актив';
      firstTh.parentNode.insertBefore(th, firstTh);
    } else if (!showAssetCol && existingAssetTh) {
      existingAssetTh.remove();
    }
  }

  const remaining = realItems.length - histShown;
  if (el.histShowMore) {
    if (remaining > 0) {
      el.histShowMore.textContent = 'Показати ще ' + Math.min(remaining, pageSize);
      el.histShowMore.classList.remove('d-none');
    } else {
      el.histShowMore.classList.add('d-none');
    }
  }
}

export function resetHistShown() { histShown = 0; }

/* ---- Stats ---- */
function computeStats(values) {
  const nums = values.filter(function (v) { return v != null && !Number.isNaN(Number(v)); }).map(Number);
  if (!nums.length) return null;
  const sorted = nums.slice().sort(function (a, b) { return a - b; });
  const sum    = sorted.reduce(function (s, v) { return s + v; }, 0);
  const mid    = Math.floor(sorted.length / 2);
  const median = sorted.length % 2 !== 0 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
  return { min: sorted[0], max: sorted[sorted.length - 1], avg: sum / sorted.length, median, count: sorted.length };
}

function renderHistStats(parsed, isMulti) {
  const box = document.getElementById('hist-stats');
  if (!box) return;
  if (!parsed || !parsed.length) { box.classList.add('d-none'); box.innerHTML = ''; return; }

  let html = '';
  parsed.forEach(function (p, idx) {
    const vals = (p.items || []).map(function (it) {
      return p.metric === 'uah' ? it.price_uah : it.price_usd;
    });
    const s = computeStats(vals);
    if (!s) return;
    const unit  = p.metricLabel || '';
    const color = CHART_COLORS[idx % CHART_COLORS.length];
    if (isMulti) {
      html += '<div class="d-flex flex-wrap gap-2 align-items-center w-100">';
      html += '<span class="hist-stat-group-label"><span class="hist-stat-dot" style="background:' + color + '"></span>' + escapeHtml(p.sym) + ' (' + unit + ')</span>';
    }
    html += '<span class="glass hist-stat-badge">Мін: '     + escapeHtml(formatPrice(s.min))    + '</span>';
    html += '<span class="glass hist-stat-badge">Макс: '    + escapeHtml(formatPrice(s.max))    + '</span>';
    html += '<span class="glass hist-stat-badge">Середнє: ' + escapeHtml(formatPrice(s.avg))    + '</span>';
    html += '<span class="glass hist-stat-badge">Медіана: '  + escapeHtml(formatPrice(s.median)) + '</span>';
    if (isMulti) html += '</div>';
  });
  box.innerHTML = html;
  box.classList.toggle('d-none', !html);
}

/* ---- Query string builder ---- */
function buildHistQueryString(sym, typ, range) {
  const qParts = ['asset_symbol=' + encodeURIComponent(sym), 'asset_type=' + encodeURIComponent(typ)];
  if (range === 'custom') {
    const dfrom = document.getElementById('hist-date-from');
    const dto   = document.getElementById('hist-date-to');
    if (dfrom && dfrom.value) qParts.push('date_from=' + encodeURIComponent(dfrom.value));
    if (dto   && dto.value)   qParts.push('date_to='   + encodeURIComponent(dto.value));
    qParts.push('range=custom');
  } else {
    qParts.push('range=' + encodeURIComponent(range));
  }
  return qParts.join('&');
}

/* ---- Multi-series helpers ---- */
function buildUnifiedTimeline(seriesArr) {
  const set = {};
  seriesArr.forEach(function (items) {
    items.forEach(function (it) {
      if (it._gap) return;
      const d = parseTimestamp(it.created_at);
      if (d) set[d.getTime()] = true;
    });
  });
  return Object.keys(set).map(Number).sort(function (a, b) { return a - b; });
}

function alignSeriesToTimeline(items, timeline, metric, toleranceMs) {
  const epochMap = [];
  items.forEach(function (it) {
    if (it._gap) { epochMap.push({ epoch: null, val: null }); return; }
    const d   = parseTimestamp(it.created_at);
    const val = metric === 'uah' ? it.price_uah : it.price_usd;
    if (d && val != null) epochMap.push({ epoch: d.getTime(), val: Number(val) });
  });
  const sorted = epochMap.filter(function (e) { return e.epoch != null; });
  return timeline.map(function (ts) {
    let best = null, bestDist = Infinity;
    for (let i = 0; i < sorted.length; i++) {
      const dist = Math.abs(sorted[i].epoch - ts);
      if (dist < bestDist) { bestDist = dist; best = sorted[i]; }
      if (sorted[i].epoch > ts) break;
    }
    if (best && bestDist <= toleranceMs) return best.val;
    return null;
  });
}

function normalizeToPctChange(values) {
  let base = null;
  for (let i = 0; i < values.length; i++) {
    if (values[i] != null) { base = values[i]; break; }
  }
  if (base == null || base === 0) return values;
  return values.map(function (v) {
    if (v == null) return null;
    return ((v - base) / base) * 100;
  });
}

/* ---- Main history loader ---- */
export async function loadHistorySeries() {
  const { el } = store;
  if (!el.histAsset || !el.histRange) return;
  const selected = getSelectedHistAssets();
  if (!selected.length) return;
  const range   = el.histRange.value;
  const isMulti = selected.length > 1;
  histMultiMode = isMulti;
  saveState({ histRange: range });

  if (el.histChartErr) { el.histChartErr.classList.add('d-none'); el.histChartErr.textContent = ''; }

  try {
    const fetches = selected.map(function (v) {
      const parts = v.split(':');
      const sym = parts[0], typ = parts[1];
      const q = buildHistQueryString(sym, typ, range);
      return fetchWithRetry('/api/history/series?' + q)
        .then(function (r) { return r.json(); })
        .then(function (data) { return { key: v, sym, typ, data }; });
    });
    const results = await Promise.all(fetches);

    const firstError = results.find(function (r) { return r.data && r.data.error; });
    if (firstError && results.length === 1) {
      if (el.histChartErr) {
        el.histChartErr.textContent = firstError.data.detail || firstError.data.error || 'Помилка';
        el.histChartErr.classList.remove('d-none');
      }
      return;
    }

    let xScaleMin = null;
    let xScaleMax = Date.now();
    if (range === '12h') {
      xScaleMin = xScaleMax - 12 * 60 * 60 * 1000;
    } else if (range === '24h') {
      xScaleMin = xScaleMax - 24 * 60 * 60 * 1000;
    } else if (range === '7d') {
      xScaleMin = xScaleMax - 7 * 24 * 60 * 60 * 1000;
    } else if (range === '30d') {
      xScaleMin = xScaleMax - 30 * 24 * 60 * 60 * 1000;
    } else if (range === 'all') {
      xScaleMin = null;
      xScaleMax = null; // Let it auto bound
    } else if (range === 'custom') {
      const dfrom = document.getElementById('hist-date-from');
      const dto   = document.getElementById('hist-date-to');
      if (dfrom && dfrom.value) xScaleMin = new Date(dfrom.value).getTime();
      else xScaleMin = null;
      if (dto && dto.value) xScaleMax = new Date(dto.value).getTime() + 86400000 - 1;
      else xScaleMax = null;
    }

    let durationMs = xScaleMax && xScaleMin ? (xScaleMax - xScaleMin) : null;
    if (!durationMs && (range === 'all' || range === 'custom')) {
      let minTs = Infinity, maxTs = -Infinity;
      results.forEach(function(r) {
        (r.data.items || []).forEach(function(it) {
          const d = parseTimestamp(it.created_at);
          if (d) {
            const ts = d.getTime();
            if (ts < minTs) minTs = ts;
            if (ts > maxTs) maxTs = ts;
          }
        });
      });
      if (minTs !== Infinity && maxTs !== -Infinity) durationMs = maxTs - minTs;
    }
    
    let bucketMs = null;
    if (durationMs) {
      if (durationMs <= 12 * 3600 * 1000) {
        bucketMs = 5 * 60 * 1000; // 5 mins — ~144 points for 12h
      } else if (durationMs <= 24 * 3600 * 1000) {
        bucketMs = 30 * 60 * 1000; // 30 mins
      } else if (durationMs <= 7 * 24 * 3600 * 1000) {
        bucketMs = 4 * 3600 * 1000; // 4 hours
      } else if (durationMs <= 31 * 24 * 3600 * 1000) {
        bucketMs = 12 * 3600 * 1000; // 12 hours
      } else if (durationMs <= 90 * 24 * 3600 * 1000) {
        bucketMs = 24 * 3600 * 1000; // 1 day
      } else {
        bucketMs = 7 * 24 * 3600 * 1000; // 1 week
      }
    }

    const parsed = [];
    const allRawItems = [];
    results.forEach(function (r) {
      let items = (r.data && r.data.items) || [];
      if (!items.length) return;
      const metric = (r.data && r.data.series_metric) || 'uah';
      
      if (bucketMs) {
        items = downsampleItems(items, bucketMs, xScaleMin, xScaleMax);
        // Recalculate pct_change_from_prev after downsampling, skipping nulls
        let lastValidItem = null;
        for (let i = 0; i < items.length; i++) {
          const curr = items[i];
          if (curr._gap) continue;
          
          if (lastValidItem) {
            const pVal = metric === 'uah' ? lastValidItem.price_uah : lastValidItem.price_usd;
            const cVal = metric === 'uah' ? curr.price_uah : curr.price_usd;
            if (pVal && cVal) {
              curr.pct_change_from_prev = ((cVal - pVal) / pVal) * 100;
            } else {
              curr.pct_change_from_prev = null;
            }
          }
          lastValidItem = curr;
        }
      }
      
      const chartItems = insertGapMarkers(items);
      items.forEach(function (it) {
        allRawItems.push({
          _sym: r.sym, _metric: metric, created_at: it.created_at,
          price_uah: it.price_uah, price_usd: it.price_usd,
          pct_change_from_prev: it.pct_change_from_prev
        });
      });
      parsed.push({ sym: r.sym, metric, metricLabel: metric === 'uah' ? 'UAH' : 'USD', items, chartItems });
    });

    const hasData = parsed.length > 0;
    if (el.histEmpty) el.histEmpty.classList.toggle('d-none', hasData);
    if (!hasData) {
      histAllItems = [];
      histShown    = 0;
      if (el.histTbody)    el.histTbody.innerHTML = '';
      if (el.histShowMore) el.histShowMore.classList.add('d-none');
      destroyChartInstance(histMainChart);
      histMainChart = null;
      return;
    }

    let datasets = [];
    let yAxisLabel = '';
    histAbsoluteValues = {};

    const theme = chartTheme();

    if (!isMulti) {
      const p  = parsed[0];
      yAxisLabel = p.metricLabel;
      const dataPoints = [];
      p.chartItems.forEach(function (it) {
        const d = parseTimestamp(it.created_at);
        if (!d) return;
        if (it._gap) {
          dataPoints.push({ x: d.getTime(), y: null });
        } else {
          dataPoints.push({ x: d.getTime(), y: Number(p.metric === 'uah' ? it.price_uah : it.price_usd) });
        }
      });
      datasets = [{
        label: p.sym + ' (' + p.metricLabel + ')',
        data: dataPoints,
        borderColor: CHART_COLORS[0], backgroundColor: CHART_COLORS[0],
        tension: 0.32, fill: false, spanGaps: true,
        segment: {
          borderDash: function(ctx) { return (ctx.p0.skip || ctx.p1.skip || ctx.p0DataIndex !== (ctx.p1DataIndex - 1)) ? [4, 4] : undefined; },
          borderColor: function(ctx) { return (ctx.p0.skip || ctx.p1.skip || ctx.p0DataIndex !== (ctx.p1DataIndex - 1)) ? theme.grid : undefined; },
          borderWidth: function(ctx) { return (ctx.p0.skip || ctx.p1.skip || ctx.p0DataIndex !== (ctx.p1DataIndex - 1)) ? 1 : undefined; }
        }
      }];
    } else {
      const allSeries   = parsed.map(function (p) { return p.chartItems; });
      const timeline    = buildUnifiedTimeline(allSeries);
      let toleranceMs = 15 * 60 * 1000;
      if (range === '12h' || range === '24h') toleranceMs = 5 * 60 * 1000;
      
      datasets = parsed.map(function (p, idx) {
        const aligned    = alignSeriesToTimeline(p.chartItems, timeline, p.metric, toleranceMs);
        histAbsoluteValues[p.sym] = aligned.slice();
        const normalized = normalizeToPctChange(aligned);
        
        const dataPoints = [];
        timeline.forEach(function(ts, i) {
          dataPoints.push({ x: ts, y: normalized[i] });
        });

        return {
          label: p.sym + ' (' + p.metricLabel + ')',
          data: dataPoints,
          borderColor: CHART_COLORS[idx % CHART_COLORS.length],
          backgroundColor: CHART_COLORS[idx % CHART_COLORS.length],
          tension: 0.32, fill: false, spanGaps: true,
          segment: {
            borderDash: function(ctx) { return (ctx.p0.skip || ctx.p1.skip || ctx.p0DataIndex !== (ctx.p1DataIndex - 1)) ? [4, 4] : undefined; },
            borderColor: function(ctx) { return (ctx.p0.skip || ctx.p1.skip || ctx.p0DataIndex !== (ctx.p1DataIndex - 1)) ? theme.grid : undefined; },
            borderWidth: function(ctx) { return (ctx.p0.skip || ctx.p1.skip || ctx.p0DataIndex !== (ctx.p1DataIndex - 1)) ? 1 : undefined; }
          },
          _sym: p.sym, _metricLabel: p.metricLabel
        };
      });
      yAxisLabel = '% зміна';
    }

    const tooltipCallbacks = {};
    if (isMulti) {
      tooltipCallbacks.label = function (ctx) {
        const ds  = ctx.dataset;
        const sym = ds._sym || ds.label;
        const ml  = ds._metricLabel || '';
        const pct = ctx.parsed.y;
        if (pct == null) return null;
        const absArr = histAbsoluteValues[sym];
        const absVal = absArr ? absArr[ctx.dataIndex] : null;
        let parts = sym + ': ' + (pct >= 0 ? '+' : '') + pct.toFixed(2) + '%';
        if (absVal != null) parts += '  (' + formatPrice(absVal) + ' ' + ml + ')';
        return parts;
      };
    }

    const ctx = document.getElementById('hist-chart');
    destroyChartInstance(histMainChart);
    histMainChart = new Chart(ctx, {
      type: 'line',
      data: { datasets },
      options: {
        responsive: true, maintainAspectRatio: false,
        interaction: { mode: 'index', intersect: false },
        plugins: {
          legend: { display: true, labels: { color: theme.text } },
          tooltip: {
            titleColor: theme.tooltipText, bodyColor: theme.tooltipText,
            backgroundColor: theme.tooltipBg, borderColor: theme.tooltipBorder,
            borderWidth: 1,
            filter: function (item) { return item.raw && item.raw.y != null; },
            callbacks: tooltipCallbacks
          }
        },
        scales: {
          x: { 
            type: 'time',
            min: xScaleMin,
            max: xScaleMax,
            time: {
              displayFormats: {
                millisecond: 'HH:mm:ss', second: 'HH:mm:ss', minute: 'HH:mm', hour: 'dd.MM HH:mm',
                day: 'dd.MM.yyyy', week: 'dd.MM.yyyy', month: 'MM.yyyy', quarter: 'MM.yyyy', year: 'yyyy'
              },
              tooltipFormat: 'dd.MM.yyyy HH:mm'
            },
            grid: { color: theme.grid }, 
            ticks: { color: theme.tick, autoSkip: true, maxTicksLimit: 12, maxRotation: 0, minRotation: 0 } 
          },
          y: { grid: { color: theme.grid }, ticks: { color: theme.tick }, title: { display: !!yAxisLabel, text: yAxisLabel || '', color: theme.tick } }
        }
      }
    });

    if (isMulti) {
      allRawItems.sort(function (a, b) {
        const da = parseTimestamp(a.created_at);
        const db = parseTimestamp(b.created_at);
        if (!da || !db) return 0;
        return db.getTime() - da.getTime();
      });
      histAllItems = allRawItems;
    } else {
      histAllItems = parsed[0] ? insertGapMarkers(parsed[0].items) : [];
    }
    histShown = 0;
    renderHistoryTable();
    renderHistStats(parsed, isMulti);
  } catch (err) {
    if (el.histChartErr) {
      el.histChartErr.textContent = 'Не вдалося завантажити історію.';
      el.histChartErr.classList.remove('d-none');
    }
    showToast('Не вдалося завантажити історію.', 'error');
  }
}

/* ---- Bind history-specific events (access to module-local state) ---- */
export function bindHistEvents() {
  const { el, st } = store;

  if (el.histLoad) {
    el.histLoad.addEventListener('click', function () {
      withButtonSpinner(el.histLoad, loadHistorySeries);
    });
  }
  if (el.histShowMore) {
    el.histShowMore.addEventListener('click', renderHistoryTable);
  }
  if (el.histPageSize && el.histPageSizeToggle && el.histPageSizeMenu) {
    wireCoSelectDropdown(el.histPageSizeToggle, el.histPageSizeMenu, el.histPageSize, function () {
      const v = parseInt(el.histPageSize.value, 10);
      if (!isNaN(v)) { st.histPageSize = v; saveState({ histPageSize: v }); }
      histShown = 0;
      renderHistoryTable();
    });
  }
  if (el.histRange && el.histRangeToggle && el.histRangeMenu) {
    wireCoSelectDropdown(el.histRangeToggle, el.histRangeMenu, el.histRange, function () {
      saveState({ histRange: el.histRange.value });
      toggleCustomRangeFields();
    });
    wireCoSelectTypeahead(el.histRangeToggle, el.histRangeMenu);
  }
  if (el.histFullscreen && el.histChartWrap) {
    el.histFullscreen.addEventListener('click', function () {
      if (document.fullscreenElement) {
        document.exitFullscreen();
      } else {
        (el.histChartWrap.requestFullscreen || el.histChartWrap.webkitRequestFullscreen || function () {}).call(el.histChartWrap);
      }
    });
    document.addEventListener('fullscreenchange', function () {
      const icon = el.histFullscreen.querySelector('i');
      if (!icon) return;
      icon.className = document.fullscreenElement ? 'bi bi-fullscreen-exit' : 'bi bi-arrows-fullscreen';
      if (histMainChart) setTimeout(function () { histMainChart.resize(); }, 150);
    });
  }
  const histTab = document.getElementById('hist-tab');
  if (histTab) {
    histTab.addEventListener('shown.bs.tab', function () {
      fillHistAssetSelect();
      if (el.histAsset && el.histAsset.value) loadHistorySeries();
    });
  }
}
