import { store, saveState } from './state.js';
import { KPI_FALLBACK, MAX_FAVORITES } from './constants.js';
import { fillHiddenSelectAndMenu, syncDropdownLabel } from './dropdowns.js';
import {
  escapeHtml, formatPrice, formatPct, trendClass, pairKey,
  displayName, displayIcon, isPopularRow, parsePairKeyString,
  parseTimestamp, formatLocalDateTime, formatRelativeTime,
  destroyChartInstance
} from './formatting.js';

/* ---- Module-local state ---- */
export const liveSort = { key: 'symbol', dir: 1 };
let sparkCharts  = {};
let prevKpiValues = ['', '', ''];
let kpiDragSrc    = null;

/* ---- Rate lookups ---- */
export function findRate(sym, type) {
  const s = sym.toUpperCase();
  return store.liveRates.find(function (x) {
    return (x.asset_symbol || '').toUpperCase() === s && x.asset_type === type;
  });
}

export function findLiveRowBySymbol(sym) {
  const s = sym.toUpperCase();
  return store.liveRates.find(function (x) {
    return (x.asset_symbol || '').toUpperCase() === s;
  });
}

export function rowForPairKey(pk) {
  const p = parsePairKeyString(pk);
  if (!p) return null;
  return findRate(p.sym, p.typ);
}

/* ---- KPI slot management ---- */
export function getKpiSlotPairKeys() {
  const seen = {};
  const fav = (store.st.favoritePairs || []).filter(function (pk) {
    if (seen[pk]) return false;
    if (!rowForPairKey(pk)) return false;
    seen[pk] = true;
    return true;
  });
  const out = [];
  let fi = 0;
  for (let slot = 0; slot < 3; slot++) {
    if (fi < fav.length) {
      out.push(fav[fi]);
      fi += 1;
    } else {
      let added = false;
      for (let j = 0; j < KPI_FALLBACK.length; j++) {
        const fk = KPI_FALLBACK[j];
        if (out.indexOf(fk) >= 0) continue;
        if (rowForPairKey(fk)) { out.push(fk); added = true; break; }
      }
      if (!added) {
        const first = store.liveRates[0];
        out.push(first ? pairKey(first) : 'USD:fiat');
      }
    }
  }
  return out;
}

function mergeThreeIntoFavoritePairs(three) {
  const old  = Array.isArray(store.st.favoritePairs) ? store.st.favoritePairs.slice() : [];
  const tail = old.filter(function (k) { return three.indexOf(k) === -1; });
  store.st.favoritePairs = three.concat(tail).slice(0, MAX_FAVORITES);
  saveState({ favoritePairs: store.st.favoritePairs });
}

function swapKpiSlots(i, j) {
  if (i === j) return;
  const three = getKpiSlotPairKeys().slice();
  const t = three[i]; three[i] = three[j]; three[j] = t;
  mergeThreeIntoFavoritePairs(three);
  updateKpis();
}

export function toggleFavoritePair(pk) {
  if (!pk || pk.indexOf(':') < 0) return;
  let arr = Array.isArray(store.st.favoritePairs) ? store.st.favoritePairs.slice() : [];
  const ix = arr.indexOf(pk);
  if (ix >= 0) {
    arr.splice(ix, 1);
  } else {
    const three = getKpiSlotPairKeys();
    const kick  = three[2];
    if (kick) arr = arr.filter(function (k) { return k !== kick; });
    if (arr.indexOf(pk) < 0) arr.push(pk);
    if (arr.length > MAX_FAVORITES) arr = arr.slice(0, MAX_FAVORITES);
  }
  store.st.favoritePairs = arr;
  saveState({ favoritePairs: arr });
}

/* ---- KPI Drag-and-drop ---- */
export function bindKpiDrag() {
  document.querySelectorAll('.kpi-slot-draggable[data-kpi-slot]').forEach(function (card) {
    const slot = parseInt(card.getAttribute('data-kpi-slot'), 10);
    if (Number.isNaN(slot)) return;
    card.addEventListener('dragstart', function (e) {
      kpiDragSrc = slot;
      card.classList.add('kpi-dragging');
      try {
        e.dataTransfer.setData('text/plain', String(slot));
        e.dataTransfer.effectAllowed = 'move';
      } catch (err) { /* ignore */ }
    });
    card.addEventListener('dragend', function () {
      card.classList.remove('kpi-dragging');
      kpiDragSrc = null;
    });
    card.addEventListener('dragover', function (e) {
      e.preventDefault();
      try { e.dataTransfer.dropEffect = 'move'; } catch (err) { /* ignore */ }
    });
    card.addEventListener('drop', function (e) {
      e.preventDefault();
      const dst = parseInt(card.getAttribute('data-kpi-slot'), 10);
      if (kpiDragSrc === null || Number.isNaN(dst) || kpiDragSrc === dst) return;
      swapKpiSlots(kpiDragSrc, dst);
    });
  });
}

/* ---- Snapshot for rate-change alerts ---- */
export function snapshotKpiRates() {
  const snap = {};
  const keys = getKpiSlotPairKeys();
  keys.forEach(function (pk) {
    const r = rowForPairKey(pk);
    if (!r) return;
    snap[pk] = r.asset_type === 'fiat' ? Number(r.price_uah) : Number(r.price_usd);
  });
  return snap;
}

/* ---- Sparklines ---- */
function sparklineColor(trendPct) {
  if (trendPct === null || trendPct === undefined || Number.isNaN(Number(trendPct))) return '#94a3b8';
  const n = Number(trendPct);
  if (n > 0) return '#4ade80';
  if (n < 0) return '#f87171';
  return '#94a3b8';
}

function destroySparkCharts() {
  Object.keys(sparkCharts).forEach(function (k) { destroyChartInstance(sparkCharts[k]); });
  sparkCharts = {};
}

function renderSparkline(canvasId, points, trendPct) {
  const ctx = document.getElementById(canvasId);
  if (!ctx || !points || !points.length) return;
  const vals = points.map(function (p) { return p.series_value; })
    .filter(function (v) { return v != null && !Number.isNaN(Number(v)); });
  if (!vals.length) return;
  destroyChartInstance(sparkCharts[canvasId]);
  const lineColor = sparklineColor(trendPct);
  sparkCharts[canvasId] = new Chart(ctx, {
    type: 'line',
    data: {
      labels: points.map(function () { return ''; }),
      datasets: [{
        data: vals, borderColor: lineColor, backgroundColor: 'transparent',
        borderWidth: 1.5, pointRadius: 0, pointHoverRadius: 0, tension: 0.42, fill: false
      }]
    },
    options: {
      responsive: true, maintainAspectRatio: false, animation: false,
      layout: { padding: 0 }, events: [],
      plugins: { legend: { display: false }, tooltip: { enabled: false } },
      scales: {
        x: { display: false, grid: { display: false }, border: { display: false } },
        y: { display: false, grid: { display: false }, border: { display: false } }
      }
    }
  });
}

/* ---- KPI flash ---- */
function flashKpiCard(slotIndex) {
  const card = document.querySelector('.kpi-slot-draggable[data-kpi-slot="' + slotIndex + '"]');
  if (!card) return;
  card.classList.remove('kpi-updated');
  void card.offsetWidth;
  card.classList.add('kpi-updated');
  card.addEventListener('animationend', function handler() {
    card.classList.remove('kpi-updated');
    card.removeEventListener('animationend', handler);
  });
}

/* ---- KPI update ---- */
export function updateKpis() {
  const { el } = store;
  const keys     = getKpiSlotPairKeys();
  const valEls   = [el.kpiUsdUah, el.kpiEurUah, el.kpiBtcUsd];
  const trendEls = [el.kpiUsdTrend, el.kpiEurTrend, el.kpiBtcTrend];

  for (let i = 0; i < 3; i++) {
    const pk = keys[i];
    const r  = rowForPairKey(pk);
    const titleEl = document.getElementById('kpi-slot-' + i + '-title');
    if (titleEl) {
      if (r) {
        const symU = (r.asset_symbol || '').toUpperCase();
        titleEl.textContent = r.asset_type === 'fiat' ? `${symU} / UAH` : `${symU} / USD`;
      } else {
        titleEl.textContent = '—';
      }
    }
    let newVal = '—';
    if (valEls[i]) {
      if (!r) {
        newVal = '—';
      } else if (r.asset_type === 'fiat' && r.price_uah != null) {
        newVal = `${formatPrice(r.price_uah)} UAH`;
      } else if (r.asset_type === 'crypto' && r.price_usd != null) {
        newVal = `${formatPrice(r.price_usd)} USD`;
      }
      valEls[i].textContent = newVal;
      if (prevKpiValues[i] && prevKpiValues[i] !== newVal) flashKpiCard(i);
      prevKpiValues[i] = newVal;
    }
    if (trendEls[i]) {
      const pkTrend = r ? pairKey(r) : '';
      const ins = pkTrend ? store.dashboardInsights[pkTrend] : null;
      const p   = ins && ins.trend_24h_pct;
      trendEls[i].className = `small mt-auto ${trendClass(p)}`;
      trendEls[i].textContent = `24 год: ${formatPct(p)}`;
    }
  }
  store.lastFetchedDate = parseTimestamp(store.liveMeta.fetched_at);
  if (el.kpiTime) {
    if (store.lastFetchedDate) {
      el.kpiTime.textContent = formatRelativeTime(store.lastFetchedDate);
      el.kpiTime.title = formatLocalDateTime(store.liveMeta.fetched_at);
    } else {
      el.kpiTime.textContent = formatLocalDateTime(store.liveMeta.fetched_at);
    }
  }
}

/* ---- Filtering & sorting ---- */
export function filterLiveRows() {
  const { el } = store;
  const q = (el.liveSearch && el.liveSearch.value || '').trim().toLowerCase();
  const t = el.liveType ? el.liveType.value : 'all';
  const showAll = el.liveShowAll && el.liveShowAll.checked;
  return store.liveRates.filter(function (r) {
    if (!q && !showAll && !isPopularRow(r)) return false;
    if (t !== 'all' && r.asset_type !== t) return false;
    if (!q) return true;
    const sym  = (r.asset_symbol || '').toLowerCase();
    const name = (r.name || '').toLowerCase();
    const dn   = displayName(r).toLowerCase();
    return sym.includes(q) || name.includes(q) || dn.includes(q);
  });
}

function liveRowSortComparable(row, key) {
  if (key === 'symbol') return (row.asset_symbol || '').toUpperCase();
  if (key === 'uah')    return row.price_uah != null ? Number(row.price_uah) : -Infinity;
  if (key === 'usd')    return row.price_usd != null ? Number(row.price_usd) : -Infinity;
  return 0;
}

function cmpLive(a, b) {
  const va = liveRowSortComparable(a, liveSort.key);
  const vb = liveRowSortComparable(b, liveSort.key);
  if (va < vb) return -liveSort.dir;
  if (va > vb) return  liveSort.dir;
  return 0;
}

/* ---- Live table render ---- */
export function renderLive() {
  const { el } = store;
  if (!el.liveTbody) return;
  destroySparkCharts();
  let rows = filterLiveRows().slice().sort(cmpLive);
  const sparkJobs = [];
  const favSet    = new Set(store.st.favoritePairs || []);

  const rowHtmls = rows.map(function (r, idx) {
    const pk   = pairKey(r);
    const ins  = store.dashboardInsights[pk];
    const trend = ins && ins.trend_24h_pct;
    const safePk   = pk.replace(/[^a-zA-Z0-9]/g, '_');
    const canvasId = `spark-${safePk}-${idx}`;
    if (ins && ins.sparkline_points && ins.sparkline_points.length) {
      sparkJobs.push({ canvasId, points: ins.sparkline_points, trendPct: trend });
    }
    const icon    = escapeHtml(displayIcon(r));
    const symEsc  = escapeHtml(r.asset_symbol || '');
    const nameEsc = escapeHtml(displayName(r));
    const uahEsc  = escapeHtml(formatPrice(r.price_uah));
    const usdEsc  = escapeHtml(formatPrice(r.price_usd));
    const pctEsc  = escapeHtml(formatPct(trend));
    const tc      = trendClass(trend);
    const pkEsc   = escapeHtml(pk);
    const starFill = favSet.has(pk) ? '-fill' : '';
    return (
      `<td class="text-center kpi-star-cell"><button type="button" class="btn btn-link btn-sm p-0 text-warning kpi-star-toggle" data-pair="${pkEsc}" aria-label="Обране"><i class="bi bi-star${starFill}"></i></button></td>` +
      `<td>${icon} <strong class="fw-bold">${symEsc}</strong><br><span class="small co-label">${nameEsc}</span></td>` +
      `<td class="text-end">${uahEsc}</td>` +
      `<td class="text-end">${usdEsc}</td>` +
      `<td class="text-end ${tc}">${pctEsc}</td>` +
      `<td><div class="spark-wrap"><canvas id="${canvasId}" height="36"></canvas></div></td>`
    );
  });

  el.liveTbody.innerHTML = rowHtmls.map(function (cells, i) {
    const ins = store.dashboardInsights[pairKey(rows[i])];
    const t24 = ins && ins.trend_24h_pct;
    let trCls = '';
    if (t24 != null && !Number.isNaN(Number(t24))) {
      if (Number(t24) >= 2)  trCls = ' class="tr-trend-up"';
      else if (Number(t24) <= -2) trCls = ' class="tr-trend-down"';
    }
    return '<tr' + trCls + '>' + cells + '</tr>';
  }).join('');

  if (el.liveEmpty) el.liveEmpty.classList.toggle('d-none', rows.length > 0);
  sparkJobs.forEach(function (job) { renderSparkline(job.canvasId, job.points, job.trendPct); });
  updateKpis();
}

/* ---- Live type filter init ---- */
export function initLiveTypeFilter() {
  const { el } = store;
  if (!el.liveType || !el.liveTypeMenu || !el.liveTypeLabel) return;
  const defs = [
    { value: 'all',    label: 'Усі' },
    { value: 'fiat',   label: 'Фіат' },
    { value: 'crypto', label: 'Крипто' }
  ];
  fillHiddenSelectAndMenu(el.liveType, el.liveTypeMenu, defs);
  el.liveType.value = store.st.liveType || 'all';
  syncDropdownLabel(el.liveType, el.liveTypeLabel);
}

/* ---- Pairs param for dashboard ---- */
export function buildPairsParam() {
  const seen  = {};
  const parts = [];
  store.liveRates.forEach(function (r) {
    const k = pairKey(r);
    if (!seen[k]) { seen[k] = true; parts.push(k); }
  });
  return parts.join(',');
}
