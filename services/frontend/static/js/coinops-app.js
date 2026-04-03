/**
 * CoinOps dashboard: live rates, converter, history chart (Chart.js, Bootstrap markup).
 * Завантажується після chart.umd.min.js та bootstrap.bundle; очікує JSON у #coinops-initial-live та #coinops-live-meta.
 *
 * Структура: утиліти форматування → завантаження вбудованого JSON → посилання на DOM → віджети dropdown
 * → стан/фільтри → рендер live → конвертер → HTTP → історія → прив’язка подій → ініт.
 */
(async function () {
  let _uiStateServerSync = false;
  let _syncTimer = null;

  function initTooltips() {
    if (typeof bootstrap === 'undefined' || !bootstrap.Tooltip) return;
    document.querySelectorAll('[data-bs-toggle="tooltip"]').forEach(function (node) {
      new bootstrap.Tooltip(node);
    });
  }

  if (!document.getElementById('live-tbody')) {
    initTooltips();
    return;
  }

  /* -------------------------------------------------------------------------- */
  /* Константи та форматування (без побічних ефектів)                            */
  /* -------------------------------------------------------------------------- */
  const POPULAR_FIAT = ['USD', 'EUR', 'GBP', 'PLN', 'CHF', 'CAD'];
  const POPULAR_CRYPTO = ['BTC', 'ETH', 'USDT', 'BNB', 'SOL', 'XRP'];
  const LS_KEY = 'coinops_ui_v2';

  function loadState() {
    try {
      const raw = localStorage.getItem(LS_KEY);
      return raw ? JSON.parse(raw) : {};
    } catch (e) { return {}; }
  }
  function saveState(patch) {
    const cur = loadState();
    Object.assign(cur, patch);
    try { localStorage.setItem(LS_KEY, JSON.stringify(cur)); } catch (e) {}
    pushHash(cur);
    if (_uiStateServerSync) {
      clearTimeout(_syncTimer);
      _syncTimer = setTimeout(function () {
        fetch('/api/v1/ui-state', {
          method: 'PUT',
          credentials: 'same-origin',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ state: loadState() })
        }).catch(function () { /* ignore */ });
      }, 500);
    }
  }

  var HASH_KEYS = ['histDefaultPair', 'histRange', 'histMetric', 'liveTypeFilter', 'theme'];
  function stateToHash(state) {
    var parts = [];
    HASH_KEYS.forEach(function (k) {
      if (state[k] != null && state[k] !== '') parts.push(encodeURIComponent(k) + '=' + encodeURIComponent(state[k]));
    });
    return parts.length ? '#' + parts.join('&') : '';
  }
  function hashToState() {
    var h = location.hash.replace(/^#/, '');
    if (!h) return {};
    var obj = {};
    h.split('&').forEach(function (seg) {
      var idx = seg.indexOf('=');
      if (idx < 0) return;
      var k = decodeURIComponent(seg.slice(0, idx));
      var v = decodeURIComponent(seg.slice(idx + 1));
      if (HASH_KEYS.indexOf(k) >= 0) obj[k] = v;
    });
    return obj;
  }
  function pushHash(state) {
    var h = stateToHash(state);
    if (h !== location.hash && h !== '#') {
      history.replaceState(null, '', h || location.pathname);
    }
  }

  const FIAT_NAMES = {
    USD: 'Долар США', EUR: 'Євро', GBP: 'Фунт стерлінгів', PLN: 'Злотий', CHF: 'Франк', CAD: 'Канадський долар',
    JPY: 'Єна', CZK: 'Крона', SEK: 'Крона', NOK: 'Крона', DKK: 'Крона', HUF: 'Форинт', RON: 'Лей',
    BGN: 'Лев', MDL: 'Лей', UAH: 'Гривня'
  };
  const CRYPTO_NAMES = {
    BTC: 'Bitcoin', ETH: 'Ethereum', USDT: 'Tether', BNB: 'BNB', SOL: 'Solana', XRP: 'XRP'
  };
  const FIAT_FLAG = { USD: '🇺🇸', EUR: '🇪🇺', GBP: '🇬🇧', PLN: '🇵🇱', CHF: '🇨🇭', CAD: '🇨🇦', UAH: '🇺🇦' };
  const CRYPTO_ICON = { BTC: '₿', ETH: 'Ξ', USDT: '₮', BNB: '◆', SOL: '◎', XRP: '✕' };

  function pad2(n) { return String(n).padStart(2, '0'); }

  /** Екранування тексту перед вставкою в innerHTML (захист від XSS у полях з API). */
  function escapeHtml(value) {
    if (value == null) return '';
    return String(value)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;');
  }

  /** Parse API timestamps consistently: naive ISO datetimes are treated as UTC (same as DB / Go Z). */
  function parseTimestamp(iso) {
    if (iso == null || iso === '') return null;
    let s = String(iso).trim();
    if (s === 'None' || s === 'null') return null;
    if (s.length >= 11 && s.charAt(10) === ' ') {
      s = `${s.slice(0, 10)}T${s.slice(11)}`;
    }
    const hasTz = /Z$/i.test(s) || /[+-]\d{2}:\d{2}$/.test(s) || /[+-]\d{4}$/.test(s);
    if (!hasTz && /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}/.test(s)) {
      s = `${s}Z`;
    }
    const d = new Date(s);
    if (!isNaN(d.getTime())) return d;
    const d2 = new Date(iso);
    return isNaN(d2.getTime()) ? null : d2;
  }
  function formatLocalDateTime(iso) {
    if (!iso) return '—';
    const d = parseTimestamp(iso);
    if (d === null) return String(iso);
    return `${pad2(d.getHours())}:${pad2(d.getMinutes())}:${pad2(d.getSeconds())} ${pad2(d.getDate())}.${pad2(d.getMonth() + 1)}.${d.getFullYear()}`;
  }
  /** Підпис осі X для графіка історії: 24h — лише час; інші періоди — дата без часу. */
  function formatChartAxisLabel(iso, range) {
    if (!iso) return '—';
    const d = parseTimestamp(iso);
    if (d === null || isNaN(d.getTime())) return String(iso);
    if (range === '24h') {
      return `${pad2(d.getHours())}:${pad2(d.getMinutes())}`;
    }
    return `${pad2(d.getDate())}.${pad2(d.getMonth() + 1)}.${d.getFullYear()}`;
  }
  function addThousandsSep(s) {
    var parts = s.split('.');
    parts[0] = parts[0].replace(/\B(?=(\d{3})+(?!\d))/g, '\u00a0');
    return parts.join('.');
  }
  function formatPrice(v) {
    if (v === null || v === undefined) return '—';
    const n = Number(v);
    if (Number.isNaN(n)) return '—';
    const abs = Math.abs(n);
    if (abs > 0 && abs < 0.01) return addThousandsSep(n.toPrecision(4));
    if (abs > 0 && abs < 1) return addThousandsSep(n.toFixed(4));
    return addThousandsSep(n.toFixed(2));
  }
  function formatPct(v) {
    if (v === null || v === undefined || Number.isNaN(Number(v))) return '—';
    const n = Number(v);
    return `${n > 0 ? '+' : ''}${n.toFixed(2)}%`;
  }
  function trendClass(v) {
    if (v === null || v === undefined || Number.isNaN(Number(v))) return 'trend-na';
    return Number(v) >= 0 ? 'trend-up' : 'trend-down';
  }
  function pairKey(r) {
    return `${(r.asset_symbol || '').toUpperCase()}:${r.asset_type || ''}`;
  }
  function displayName(r) {
    const sym = (r.asset_symbol || '').toUpperCase();
    if (r.asset_type === 'fiat') return FIAT_NAMES[sym] || (r.name || sym);
    return CRYPTO_NAMES[sym] || sym;
  }
  function displayIcon(r) {
    const sym = (r.asset_symbol || '').toUpperCase();
    if (r.asset_type === 'fiat') return FIAT_FLAG[sym] || '💱';
    return CRYPTO_ICON[sym] || '◆';
  }
  function isPopularRow(r) {
    const sym = (r.asset_symbol || '').toUpperCase();
    if (r.asset_type === 'fiat') return POPULAR_FIAT.includes(sym);
    if (r.asset_type === 'crypto') return POPULAR_CRYPTO.includes(sym);
    return false;
  }

  const HIST_PAGE_SIZES = [15, 30, 50];
  const HIST_DEFAULT_PAGE = 15;
  const AUTO_REFRESH_INTERVAL_MS = 60000;
  const MAX_FAVORITES = 8;
  const KPI_FALLBACK = ['USD:fiat', 'EUR:fiat', 'BTC:crypto'];

  function parsePairKeyString(pk) {
    if (pk == null || typeof pk !== 'string') return null;
    const idx = pk.lastIndexOf(':');
    if (idx <= 0) return null;
    return { sym: pk.slice(0, idx).toUpperCase(), typ: pk.slice(idx + 1) };
  }

  function rowForPairKey(pk) {
    const p = parsePairKeyString(pk);
    if (!p) return null;
    return findRate(p.sym, p.typ);
  }

  function normalizeUiState(s) {
    if (!Array.isArray(s.favoritePairs)) s.favoritePairs = [];
    s.favoritePairs = s.favoritePairs.filter(function (x) { return typeof x === 'string' && x.indexOf(':') > 0; });
    if (s.favoritePairs.length > MAX_FAVORITES) s.favoritePairs = s.favoritePairs.slice(0, MAX_FAVORITES);
    if (s.histDefaultPair != null && typeof s.histDefaultPair !== 'string') s.histDefaultPair = null;
    if (s.convFrom != null && typeof s.convFrom !== 'string') delete s.convFrom;
    if (s.convTo != null && typeof s.convTo !== 'string') delete s.convTo;
    if (s.convAmount != null && typeof s.convAmount !== 'string') s.convAmount = String(s.convAmount);
    if (!s.uiStateVersion) s.uiStateVersion = 2;
  }

  function getKpiSlotPairKeys() {
    const seen = {};
    const fav = (st.favoritePairs || []).filter(function (pk) {
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
          if (rowForPairKey(fk)) {
            out.push(fk);
            added = true;
            break;
          }
        }
        if (!added) {
          const first = liveRates[0];
          out.push(first ? pairKey(first) : 'USD:fiat');
        }
      }
    }
    return out;
  }

  function mergeThreeIntoFavoritePairs(three) {
    const old = Array.isArray(st.favoritePairs) ? st.favoritePairs.slice() : [];
    const tail = old.filter(function (k) { return three.indexOf(k) === -1; });
    st.favoritePairs = three.concat(tail).slice(0, MAX_FAVORITES);
    saveState({ favoritePairs: st.favoritePairs });
  }

  function swapKpiSlots(i, j) {
    if (i === j) return;
    const three = getKpiSlotPairKeys().slice();
    const t = three[i];
    three[i] = three[j];
    three[j] = t;
    mergeThreeIntoFavoritePairs(three);
    updateKpis();
  }

  function toggleFavoritePair(pk) {
    if (!pk || pk.indexOf(':') < 0) return;
    let arr = Array.isArray(st.favoritePairs) ? st.favoritePairs.slice() : [];
    const ix = arr.indexOf(pk);
    if (ix >= 0) {
      arr.splice(ix, 1);
    } else {
      const three = getKpiSlotPairKeys();
      const kick = three[2];
      if (kick) {
        arr = arr.filter(function (k) { return k !== kick; });
      }
      if (arr.indexOf(pk) < 0) {
        arr.push(pk);
      }
      if (arr.length > MAX_FAVORITES) {
        arr = arr.slice(0, MAX_FAVORITES);
      }
    }
    st.favoritePairs = arr;
    saveState({ favoritePairs: arr });
  }

  let _kpiDragSrc = null;

  function bindKpiDrag() {
    document.querySelectorAll('.kpi-slot-draggable[data-kpi-slot]').forEach(function (card) {
      const slot = parseInt(card.getAttribute('data-kpi-slot'), 10);
      if (Number.isNaN(slot)) return;
      card.addEventListener('dragstart', function (e) {
        _kpiDragSrc = slot;
        card.classList.add('kpi-dragging');
        try {
          e.dataTransfer.setData('text/plain', String(slot));
          e.dataTransfer.effectAllowed = 'move';
        } catch (err) { /* ignore */ }
      });
      card.addEventListener('dragend', function () {
        card.classList.remove('kpi-dragging');
        _kpiDragSrc = null;
      });
      card.addEventListener('dragover', function (e) {
        e.preventDefault();
        try { e.dataTransfer.dropEffect = 'move'; } catch (err) { /* ignore */ }
      });
      card.addEventListener('drop', function (e) {
        e.preventDefault();
        const dst = parseInt(card.getAttribute('data-kpi-slot'), 10);
        const src = _kpiDragSrc;
        if (src === null || Number.isNaN(dst) || src === dst) return;
        swapKpiSlots(src, dst);
      });
    });
  }

  /* -------------------------------------------------------------------------- */
  /* Вбудований JSON з Jinja (<script type="application/json">)                  */
  /* -------------------------------------------------------------------------- */
  const liveJsonEl = document.getElementById('coinops-initial-live');
  const metaJsonEl = document.getElementById('coinops-live-meta');
  const clientErrEl = document.getElementById('coinops-client-error');

  function showClientConfigError(message) {
    if (!clientErrEl || !message) return;
    clientErrEl.textContent = message;
    clientErrEl.classList.remove('d-none');
  }

  let initialLive = [];
  const parseProblems = [];
  try {
    const rawLive = (liveJsonEl && liveJsonEl.textContent) ? liveJsonEl.textContent.trim() : '[]';
    initialLive = JSON.parse(rawLive || '[]');
  } catch (e) {
    parseProblems.push('початкові курси');
    initialLive = [];
  }
  if (!Array.isArray(initialLive)) {
    parseProblems.push('поле курсів не є масивом');
    initialLive = [];
  }

  let liveMeta = {};
  try {
    const rawMeta = (metaJsonEl && metaJsonEl.textContent) ? metaJsonEl.textContent.trim() : '{}';
    liveMeta = JSON.parse(rawMeta || '{}');
  } catch (e) {
    parseProblems.push('метадані оновлення');
    liveMeta = {};
  }
  if (parseProblems.length) {
    showClientConfigError(
      `Не вдалося розібрати вбудований JSON на сторінці (${parseProblems.join(', ')}). Спробуйте оновити сторінку.`
    );
  }

  let liveRates = Array.isArray(initialLive) ? initialLive.slice() : [];
  let dashboardInsights = {};
  let liveSort = { key: 'symbol', dir: 1 };
  let sparkCharts = {};
  let _histAllItems = [];
  let _histShown = 0;
  let _autoRefreshId = null;
  let _relativeTimeId = null;
  let _lastFetchedDate = null;

  function insertGapMarkers(items) {
    if (!items || items.length < 2) return items;
    var timestamps = items.map(function (it) {
      var d = parseTimestamp(it.created_at);
      return d ? d.getTime() : 0;
    });
    var diffs = [];
    for (var i = 1; i < timestamps.length; i++) {
      var diff = timestamps[i] - timestamps[i - 1];
      if (diff > 0) diffs.push(diff);
    }
    if (!diffs.length) return items;
    diffs.sort(function (a, b) { return a - b; });
    var median = diffs[Math.floor(diffs.length / 2)];
    var threshold = median * 3;
    var minGap = 30 * 60 * 1000;
    if (threshold < minGap) threshold = minGap;
    var result = [items[0]];
    for (var j = 1; j < items.length; j++) {
      var gap = timestamps[j] - timestamps[j - 1];
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

  function withButtonSpinner(btn, asyncFn) {
    if (!btn) return asyncFn();
    var original = btn.innerHTML;
    btn.disabled = true;
    btn.innerHTML = '<span class="spinner-border spinner-border-sm" role="status" aria-hidden="true"></span>';
    return asyncFn().finally(function () {
      btn.innerHTML = original;
      btn.disabled = false;
    });
  }

  function formatRelativeTime(date) {
    if (!date) return '';
    var diff = Math.max(0, Date.now() - date.getTime());
    var sec = Math.floor(diff / 1000);
    if (sec < 60) return sec + '\u00a0\u0441 \u0442\u043e\u043c\u0443';
    var min = Math.floor(sec / 60);
    if (min < 60) return min + '\u00a0\u0445\u0432 \u0442\u043e\u043c\u0443';
    return Math.floor(min / 60) + '\u00a0\u0433\u043e\u0434 \u0442\u043e\u043c\u0443';
  }

  function showToast(message, type) {
    var box = document.getElementById('toast-box');
    if (!box) return;
    var id = 'toast-' + Date.now();
    var cls = 'toast-' + (type || 'info');
    var html =
      '<div id="' + id + '" class="toast toast-glass ' + cls + '" role="alert" aria-live="assertive" aria-atomic="true" data-bs-delay="5000">' +
        '<div class="d-flex">' +
          '<div class="toast-body">' + escapeHtml(message) + '</div>' +
          '<button type="button" class="btn-close me-2 m-auto" data-bs-dismiss="toast" aria-label="Закрити"></button>' +
        '</div>' +
      '</div>';
    box.insertAdjacentHTML('beforeend', html);
    var el = document.getElementById(id);
    if (el && typeof bootstrap !== 'undefined' && bootstrap.Toast) {
      var t = new bootstrap.Toast(el);
      t.show();
      el.addEventListener('hidden.bs.toast', function () { el.remove(); });
    }
  }

  var RATE_CHANGE_THRESHOLD_PCT = 1;
  var _prevKpiRates = {};

  function detectRateAlerts(oldRates, newRates) {
    if (!oldRates || !Object.keys(oldRates).length) return;
    var keys = getKpiSlotPairKeys();
    keys.forEach(function (pk) {
      var oldVal = oldRates[pk];
      var newRow = rowForPairKey(pk);
      if (!newRow || oldVal == null) return;
      var newVal = newRow.asset_type === 'fiat' ? Number(newRow.price_uah) : Number(newRow.price_usd);
      if (!newVal || Number.isNaN(newVal) || Number.isNaN(oldVal)) return;
      var pctChange = ((newVal - oldVal) / oldVal) * 100;
      if (Math.abs(pctChange) >= RATE_CHANGE_THRESHOLD_PCT) {
        var sym = (newRow.asset_symbol || '').toUpperCase();
        var arrow = pctChange > 0 ? '\u2191' : '\u2193';
        var sign = pctChange > 0 ? '+' : '';
        showToast(sym + ' ' + arrow + ' ' + sign + pctChange.toFixed(2) + '%', pctChange > 0 ? 'success' : 'warning');
      }
    });
  }

  function snapshotKpiRates() {
    var snap = {};
    var keys = getKpiSlotPairKeys();
    keys.forEach(function (pk) {
      var r = rowForPairKey(pk);
      if (!r) return;
      snap[pk] = r.asset_type === 'fiat' ? Number(r.price_uah) : Number(r.price_usd);
    });
    return snap;
  }

  function fetchWithRetry(url, opts, cfg) {
    var retries = (cfg && cfg.retries) || 3;
    var baseDelay = (cfg && cfg.baseDelay) || 1000;
    function attempt(n) {
      return fetch(url, opts).then(function (res) {
        if (res.status >= 500 && n < retries) {
          return new Promise(function (resolve) {
            setTimeout(resolve, baseDelay * Math.pow(2, n));
          }).then(function () { return attempt(n + 1); });
        }
        return res;
      }).catch(function (err) {
        if (n < retries) {
          return new Promise(function (resolve) {
            setTimeout(resolve, baseDelay * Math.pow(2, n));
          }).then(function () { return attempt(n + 1); });
        }
        throw err;
      });
    }
    return attempt(0);
  }

  function startRelativeTimeTicker() {
    if (_relativeTimeId) clearInterval(_relativeTimeId);
    _relativeTimeId = setInterval(function () {
      if (!_lastFetchedDate || !el.kpiTime) return;
      el.kpiTime.textContent = formatRelativeTime(_lastFetchedDate);
      el.kpiTime.title = formatLocalDateTime(liveMeta.fetched_at);
    }, 1000);
  }

  /* -------------------------------------------------------------------------- */
  /* Посилання на DOM (id з шаблону не змінювати — на них зав’язаний JS/CSS)    */
  /* -------------------------------------------------------------------------- */
  const base = loadState();
  try {
    const r = await fetch('/api/v1/ui-state', { credentials: 'same-origin' });
    const data = await r.json();
    if (data && data.enabled === true) {
      _uiStateServerSync = true;
    }
    if (data && data.enabled && data.state && typeof data.state === 'object') {
      Object.assign(base, data.state);
      try { localStorage.setItem(LS_KEY, JSON.stringify(base)); } catch (e) {}
    }
  } catch (e) { /* ignore */ }
  var fromHash = hashToState();
  Object.assign(base, fromHash);
  const st = base;
  normalizeUiState(st);
  const el = {
    liveSearch: document.getElementById('live-search'),
    liveType: document.getElementById('live-type-filter'),
    liveTypeMenu: document.getElementById('live-type-menu'),
    liveTypeToggle: document.getElementById('live-type-toggle'),
    liveTypeLabel: document.getElementById('live-type-label'),
    liveShowAll: document.getElementById('live-show-all'),
    liveTbody: document.getElementById('live-tbody'),
    liveTable: document.getElementById('live-table'),
    kpiUsdUah: document.getElementById('kpi-usd-uah'),
    kpiEurUah: document.getElementById('kpi-eur-uah'),
    kpiBtcUsd: document.getElementById('kpi-btc-usd'),
    kpiUsdTrend: document.getElementById('kpi-usd-trend'),
    kpiEurTrend: document.getElementById('kpi-eur-trend'),
    kpiBtcTrend: document.getElementById('kpi-btc-trend'),
    kpiTime: document.getElementById('kpi-live-time'),
    btnRefresh: document.getElementById('btn-refresh-live'),
    convAmount: document.getElementById('conv-amount'),
    convFrom: document.getElementById('conv-from'),
    convTo: document.getElementById('conv-to'),
    convFromMenu: document.getElementById('conv-from-menu'),
    convToMenu: document.getElementById('conv-to-menu'),
    convFromToggle: document.getElementById('conv-from-toggle'),
    convToToggle: document.getElementById('conv-to-toggle'),
    convFromLabel: document.getElementById('conv-from-label'),
    convToLabel: document.getElementById('conv-to-label'),
    convResult: document.getElementById('converter-result'),
    histAsset: document.getElementById('hist-asset'),
    histAssetMenu: document.getElementById('hist-asset-menu'),
    histAssetToggle: document.getElementById('hist-asset-toggle'),
    histAssetLabel: document.getElementById('hist-asset-label'),
    histRange: document.getElementById('hist-range'),
    histRangeMenu: document.getElementById('hist-range-menu'),
    histRangeToggle: document.getElementById('hist-range-toggle'),
    histRangeLabel: document.getElementById('hist-range-label'),
    histLoad: document.getElementById('hist-load'),
    histTbody: document.getElementById('hist-tbody'),
    histEmpty: document.getElementById('hist-empty'),
    histChartErr: document.getElementById('hist-chart-error'),
    histChartWrap: document.getElementById('hist-chart-wrap'),
    histFullscreen: document.getElementById('hist-fullscreen'),
    histShowMore: document.getElementById('hist-show-more'),
    histPageSizeMenu: document.getElementById('hist-page-size-menu'),
    histPageSizeToggle: document.getElementById('hist-page-size-toggle'),
    histPageSizeLabel: document.getElementById('hist-page-size-label'),
    histPageSize: document.getElementById('hist-page-size'),
    liveEmpty: document.getElementById('live-empty'),
  };

  if (el.liveSearch) { el.liveSearch.value = st.liveSearch || ''; }
  if (el.liveShowAll) { el.liveShowAll.checked = !!st.liveShowAll; }
  if (el.convAmount && st.convAmount != null && st.convAmount !== '') {
    el.convAmount.value = st.convAmount;
  }

  let histMainChart = null;

  /* -------------------------------------------------------------------------- */
  /* Dropdown + прихований <select> (Bootstrap 5)                                 */
  /* -------------------------------------------------------------------------- */

  /** Один пункт меню з data-value — спільна розмітка для всіх co-select. */
  function createDropdownMenuItem(value, labelText, buttonClassName) {
    const li = document.createElement('li');
    const btn = document.createElement('button');
    btn.type = 'button';
    btn.className = buttonClassName || 'dropdown-item';
    btn.setAttribute('data-value', value);
    btn.textContent = labelText;
    li.appendChild(btn);
    return li;
  }

  /** Синхронне заповнення прихованого select і ul меню з однаковим набором опцій. */
  function fillHiddenSelectAndMenu(selectEl, menuEl, pairs) {
    selectEl.innerHTML = '';
    menuEl.innerHTML = '';
    pairs.forEach(function (p) {
      selectEl.appendChild(new Option(p.label, p.value));
      menuEl.appendChild(createDropdownMenuItem(p.value, p.label));
    });
  }

  /** Уникаємо дублювання try/catch при знищенні екземплярів Chart.js. */
  function destroyChartInstance(chart) {
    if (!chart) return;
    try {
      chart.destroy();
    } catch (e) { /* ignore */ }
  }

  function destroySparkCharts() {
    Object.keys(sparkCharts).forEach(function (k) {
      destroyChartInstance(sparkCharts[k]);
    });
    sparkCharts = {};
  }

  function syncDropdownLabel(selectEl, labelEl) {
    if (!selectEl || !labelEl) return;
    const opt = selectEl.options[selectEl.selectedIndex];
    labelEl.textContent = opt ? opt.text : '—';
  }

  /** Кастомний випадаючий список (Bootstrap Dropdown) замість нативного <select> — без білої ОС-окантовки. */
  function wireCoSelectDropdown(toggleBtn, menuEl, selectEl, onPick) {
    if (!toggleBtn || !menuEl || !selectEl) return;
    const labelSpan = toggleBtn.querySelector('[data-co-select-label]');
    menuEl.addEventListener('click', function (ev) {
      const item = ev.target.closest('button[data-value]');
      if (!item || !menuEl.contains(item)) return;
      ev.preventDefault();
      selectEl.value = item.getAttribute('data-value');
      syncDropdownLabel(selectEl, labelSpan);
      if (onPick) onPick();
      if (typeof bootstrap !== 'undefined' && bootstrap.Dropdown) {
        const inst = bootstrap.Dropdown.getInstance(toggleBtn);
        if (inst) inst.hide();
      }
    });
  }

  /** Під час відкритого меню: перша літера тексту пункту — фокус і прокрутка (аналог type-ahead у select). */
  function wireCoSelectTypeahead(toggleBtn, menuEl) {
    if (!toggleBtn || !menuEl) return;
    let handler = null;
    toggleBtn.addEventListener('shown.bs.dropdown', function () {
      handler = function (e) {
        if (e.key.length !== 1 || e.ctrlKey || e.metaKey || e.altKey) return;
        const ch = e.key.toLowerCase();
        const items = menuEl.querySelectorAll('button[data-value]');
        for (const node of items) {
          const t = (node.textContent || '').trim().toLowerCase();
          if (t.startsWith(ch)) {
            node.focus();
            node.scrollIntoView({ block: 'nearest' });
            e.preventDefault();
            break;
          }
        }
      };
      document.addEventListener('keydown', handler, true);
    });
    toggleBtn.addEventListener('hidden.bs.dropdown', function () {
      if (handler) {
        document.removeEventListener('keydown', handler, true);
        handler = null;
      }
    });
  }

  function initLiveTypeFilter() {
    if (!el.liveType || !el.liveTypeMenu || !el.liveTypeLabel) return;
    const defs = [
      { value: 'all', label: 'Усі' },
      { value: 'fiat', label: 'Фіат' },
      { value: 'crypto', label: 'Крипто' }
    ];
    fillHiddenSelectAndMenu(el.liveType, el.liveTypeMenu, defs);
    el.liveType.value = st.liveType || 'all';
    syncDropdownLabel(el.liveType, el.liveTypeLabel);
  }

  function toggleCustomRangeFields() {
    var wrap = document.getElementById('hist-custom-range-wrap');
    if (!wrap) return;
    wrap.classList.toggle('d-none', el.histRange.value !== 'custom');
  }

  function initHistRangeFilter() {
    if (!el.histRange || !el.histRangeMenu || !el.histRangeLabel) return;
    const defs = [
      { value: '24h', label: '24 години' },
      { value: '7d', label: '7 днів' },
      { value: '30d', label: '1 місяць' },
      { value: 'all', label: 'Увесь час' },
      { value: 'custom', label: 'Свій діапазон' }
    ];
    fillHiddenSelectAndMenu(el.histRange, el.histRangeMenu, defs);
    const saved = st.histRange || '7d';
    const allowed = new Set(defs.map(function (d) { return d.value; }));
    el.histRange.value = allowed.has(saved) ? saved : '7d';
    syncDropdownLabel(el.histRange, el.histRangeLabel);
    toggleCustomRangeFields();
  }

  function findRate(sym, type) {
    const s = sym.toUpperCase();
    return liveRates.find(function (x) {
      return (x.asset_symbol || '').toUpperCase() === s && x.asset_type === type;
    });
  }

  /** Перший рядок за символом (без фільтра типу) — як у попередній логіці конвертера / UAH per USD. */
  function findLiveRowBySymbol(sym) {
    const s = sym.toUpperCase();
    return liveRates.find(function (x) {
      return (x.asset_symbol || '').toUpperCase() === s;
    });
  }

  let _prevKpiValues = ['', '', ''];

  function flashKpiCard(slotIndex) {
    var card = document.querySelector('.kpi-slot-draggable[data-kpi-slot="' + slotIndex + '"]');
    if (!card) return;
    card.classList.remove('kpi-updated');
    void card.offsetWidth;
    card.classList.add('kpi-updated');
    card.addEventListener('animationend', function handler() {
      card.classList.remove('kpi-updated');
      card.removeEventListener('animationend', handler);
    });
  }

  function updateKpis() {
    const keys = getKpiSlotPairKeys();
    const valEls = [el.kpiUsdUah, el.kpiEurUah, el.kpiBtcUsd];
    const trendEls = [el.kpiUsdTrend, el.kpiEurTrend, el.kpiBtcTrend];
    for (let i = 0; i < 3; i++) {
      const pk = keys[i];
      const r = rowForPairKey(pk);
      const titleEl = document.getElementById('kpi-slot-' + i + '-title');
      if (titleEl) {
        if (r) {
          const symU = (r.asset_symbol || '').toUpperCase();
          titleEl.textContent = r.asset_type === 'fiat' ? `${symU} / UAH` : `${symU} / USD`;
        } else {
          titleEl.textContent = '—';
        }
      }
      var newVal = '—';
      if (valEls[i]) {
        if (!r) {
          newVal = '—';
        } else if (r.asset_type === 'fiat' && r.price_uah != null) {
          newVal = `${formatPrice(r.price_uah)} UAH`;
        } else if (r.asset_type === 'crypto' && r.price_usd != null) {
          newVal = `${formatPrice(r.price_usd)} USD`;
        }
        valEls[i].textContent = newVal;
        if (_prevKpiValues[i] && _prevKpiValues[i] !== newVal) {
          flashKpiCard(i);
        }
        _prevKpiValues[i] = newVal;
      }
      if (trendEls[i]) {
        const pkTrend = r ? pairKey(r) : '';
        const ins = pkTrend ? dashboardInsights[pkTrend] : null;
        const p = ins && ins.trend_24h_pct;
        trendEls[i].className = `small mt-auto ${trendClass(p)}`;
        trendEls[i].textContent = `24 год: ${formatPct(p)}`;
      }
    }
    _lastFetchedDate = parseTimestamp(liveMeta.fetched_at);
    if (el.kpiTime) {
      if (_lastFetchedDate) {
        el.kpiTime.textContent = formatRelativeTime(_lastFetchedDate);
        el.kpiTime.title = formatLocalDateTime(liveMeta.fetched_at);
      } else {
        el.kpiTime.textContent = formatLocalDateTime(liveMeta.fetched_at);
      }
    }
  }

  function filterLiveRows() {
    const q = (el.liveSearch && el.liveSearch.value || '').trim().toLowerCase();
    const t = el.liveType ? el.liveType.value : 'all';
    const showAll = el.liveShowAll && el.liveShowAll.checked;
    return liveRates.filter(function (r) {
      if (!q) {
        if (!showAll && !isPopularRow(r)) return false;
      }
      if (t !== 'all' && r.asset_type !== t) return false;
      if (!q) return true;
      const sym = (r.asset_symbol || '').toLowerCase();
      const name = (r.name || '').toLowerCase();
      const dn = displayName(r).toLowerCase();
      return sym.includes(q) || name.includes(q) || dn.includes(q);
    });
  }

  function liveRowSortComparable(row, key) {
    if (key === 'symbol') return (row.asset_symbol || '').toUpperCase();
    if (key === 'uah') return row.price_uah != null ? Number(row.price_uah) : -Infinity;
    if (key === 'usd') return row.price_usd != null ? Number(row.price_usd) : -Infinity;
    return 0;
  }

  function cmpLive(a, b) {
    const k = liveSort.key;
    const va = liveRowSortComparable(a, k);
    const vb = liveRowSortComparable(b, k);
    if (va < vb) return -liveSort.dir;
    if (va > vb) return liveSort.dir;
    return 0;
  }

  function sparklineColor(trendPct) {
    if (trendPct === null || trendPct === undefined || Number.isNaN(Number(trendPct))) return '#94a3b8';
    const n = Number(trendPct);
    if (n > 0) return '#4ade80';
    if (n < 0) return '#f87171';
    return '#94a3b8';
  }

  function renderSparkline(canvasId, points, trendPct) {
    const ctx = document.getElementById(canvasId);
    if (!ctx || !points || !points.length) return;
    const vals = points.map(function (p) { return p.series_value; }).filter(function (v) { return v != null && !Number.isNaN(Number(v)); });
    if (!vals.length) return;
    destroyChartInstance(sparkCharts[canvasId]);
    const lineColor = sparklineColor(trendPct);
    sparkCharts[canvasId] = new Chart(ctx, {
      type: 'line',
      data: {
        labels: points.map(function () { return ''; }),
        datasets: [{
          data: vals,
          borderColor: lineColor,
          backgroundColor: 'transparent',
          borderWidth: 1.5,
          pointRadius: 0,
          pointHoverRadius: 0,
          tension: 0.42,
          fill: false
        }]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        animation: false,
        layout: { padding: 0 },
        events: [],
        plugins: { legend: { display: false }, tooltip: { enabled: false } },
        scales: {
          x: { display: false, grid: { display: false }, border: { display: false } },
          y: { display: false, grid: { display: false }, border: { display: false } }
        }
      }
    });
  }

  /* -------------------------------------------------------------------------- */
  /* Рендер live-таблиці та спарклайнів (дані вже в liveRates / dashboardInsights) */
  /* -------------------------------------------------------------------------- */
  function renderLive() {
    if (!el.liveTbody) return;
    destroySparkCharts();
    let rows = filterLiveRows();
    rows = rows.slice().sort(cmpLive);
    // Один запис innerHTML у tbody зменшує reflow; escapeHtml на полях з API.
    const sparkJobs = [];
    const favSet = new Set(st.favoritePairs || []);
    const rowHtmls = rows.map(function (r, idx) {
      const pk = pairKey(r);
      const ins = dashboardInsights[pk];
      const trend = ins && ins.trend_24h_pct;
      const safePk = pk.replace(/[^a-zA-Z0-9]/g, '_');
      const canvasId = `spark-${safePk}-${idx}`;
      if (ins && ins.sparkline_points && ins.sparkline_points.length) {
        sparkJobs.push({ canvasId, points: ins.sparkline_points, trendPct: trend });
      }
      const icon = escapeHtml(displayIcon(r));
      const symEsc = escapeHtml(r.asset_symbol || '');
      const nameEsc = escapeHtml(displayName(r));
      const uahEsc = escapeHtml(formatPrice(r.price_uah));
      const usdEsc = escapeHtml(formatPrice(r.price_usd));
      const pctEsc = escapeHtml(formatPct(trend));
      const tc = trendClass(trend);
      const pkEsc = escapeHtml(pk);
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
      var row = rows[i];
      var ins = dashboardInsights[pairKey(row)];
      var t24 = ins && ins.trend_24h_pct;
      var trCls = '';
      if (t24 != null && !Number.isNaN(Number(t24))) {
        if (Number(t24) >= 2) trCls = ' class="tr-trend-up"';
        else if (Number(t24) <= -2) trCls = ' class="tr-trend-down"';
      }
      return '<tr' + trCls + '>' + cells + '</tr>';
    }).join('');
    if (el.liveEmpty) {
      el.liveEmpty.classList.toggle('d-none', rows.length > 0);
    }
    sparkJobs.forEach(function (job) {
      renderSparkline(job.canvasId, job.points, job.trendPct);
    });
    updateKpis();
  }

  /* -------------------------------------------------------------------------- */
  /* Конвертер (через USD; read-only обчислення поверх liveRates)               */
  /* -------------------------------------------------------------------------- */
  function getUsdPerUnit(r) {
    if (!r) return null;
    const sym = (r.asset_symbol || '').toUpperCase();
    if (sym === 'USD' && r.price_usd != null) return 1;
    if (r.price_usd != null) return Number(r.price_usd);
    return null;
  }
  function getUahPerUsd() {
    const usd = findLiveRowBySymbol('USD');
    if (!usd || usd.price_uah == null) return null;
    return Number(usd.price_uah);
  }
  function usdValueOf(amount, symbol) {
    const sym = symbol.toUpperCase();
    if (sym === 'UAH') {
      const uahPerUsd = getUahPerUsd();
      if (!uahPerUsd || uahPerUsd <= 0) return null;
      return amount / uahPerUsd;
    }
    const r = findLiveRowBySymbol(sym);
    const u = getUsdPerUnit(r);
    if (u == null || Number.isNaN(u)) return null;
    return amount * u;
  }
  function amountFromUsd(usdAmt, symbol) {
    const sym = symbol.toUpperCase();
    if (sym === 'UAH') {
      const uahPerUsd = getUahPerUsd();
      if (!uahPerUsd || uahPerUsd <= 0) return null;
      return usdAmt * uahPerUsd;
    }
    const r = findLiveRowBySymbol(sym);
    const u = getUsdPerUnit(r);
    if (u == null || u <= 0) return null;
    return usdAmt / u;
  }
  function buildConverterSymbols() {
    const set = {};
    liveRates.forEach(function (r) {
      const s = (r.asset_symbol || '').toUpperCase();
      if (s) set[s] = true;
    });
    set['UAH'] = true;
    return Object.keys(set).sort();
  }
  function fillConverterSelects() {
    if (!el.convFrom || !el.convTo || !el.convFromMenu || !el.convToMenu) return;
    const syms = buildConverterSymbols();
    el.convFrom.innerHTML = '';
    el.convTo.innerHTML = '';
    el.convFromMenu.innerHTML = '';
    el.convToMenu.innerHTML = '';
    syms.forEach(function (s) {
      el.convFrom.appendChild(new Option(s, s));
      el.convTo.appendChild(new Option(s, s));
      const itemFrom = createDropdownMenuItem(s, s);
      const itemTo = createDropdownMenuItem(s, s);
      el.convFromMenu.appendChild(itemFrom);
      el.convToMenu.appendChild(itemTo);
    });
    const wantFrom = st.convFrom && syms.includes(st.convFrom) ? st.convFrom : null;
    const wantTo = st.convTo && syms.includes(st.convTo) ? st.convTo : null;
    if (wantFrom) el.convFrom.value = wantFrom;
    else if (syms.includes('USD')) el.convFrom.value = 'USD';
    if (wantTo) el.convTo.value = wantTo;
    else if (syms.includes('UAH')) el.convTo.value = 'UAH';
    else if (syms.length > 1) el.convTo.value = syms[1];
    syncDropdownLabel(el.convFrom, el.convFromLabel);
    syncDropdownLabel(el.convTo, el.convToLabel);
  }
  function updateConverter() {
    if (!el.convResult) return;
    const amt = parseFloat(el.convAmount && el.convAmount.value);
    const from = el.convFrom && el.convFrom.value;
    const to = el.convTo && el.convTo.value;
    if (Number.isNaN(amt) || !from || !to) {
      el.convResult.textContent = '—';
      return;
    }
    if (from === to) {
      el.convResult.textContent = `${formatPrice(amt)} ${to}`;
      return;
    }
    const usd = usdValueOf(amt, from);
    if (usd == null) {
      el.convResult.textContent = 'Недостатньо даних для цієї пари (потрібні курси USD/UAH або price_usd).';
      return;
    }
    const out = amountFromUsd(usd, to);
    if (out == null) {
      el.convResult.textContent = 'Конвертація недоступна для обраної пари.';
      return;
    }
    el.convResult.textContent = `${formatPrice(out)} ${to}  (≈ ${formatPrice(usd)} USD)`;
  }

  /* -------------------------------------------------------------------------- */
  /* HTTP: live refresh та зведення dashboard/history (окремо від рендеру таблиць) */
  /* -------------------------------------------------------------------------- */
  function buildPairsParam() {
    const seen = {};
    const parts = [];
    liveRates.forEach(function (r) {
      const k = pairKey(r);
      if (!seen[k]) {
        seen[k] = true;
        parts.push(k);
      }
    });
    return parts.join(',');
  }

  async function fetchDashboard() {
    const pairs = buildPairsParam();
    if (!pairs) {
      dashboardInsights = {};
      renderLive();
      return;
    }
    try {
      const res = await fetchWithRetry(`/api/history/dashboard?pairs=${encodeURIComponent(pairs)}`);
      const data = await res.json();
      dashboardInsights = {};
      if (data.items && Array.isArray(data.items)) {
        data.items.forEach(function (it) {
          dashboardInsights[pairKey(it)] = it;
        });
      }
    } catch (e) {
      dashboardInsights = {};
    }
    renderLive();
  }

  async function _doRefreshLive() {
    var prevSnap = snapshotKpiRates();
    try {
      const res = await fetchWithRetry('/api/live');
      const data = await res.json();
      if (data.error) return;
      liveRates = Array.isArray(data.rates) ? data.rates.slice() : [];
      liveMeta = { fetched_at: data.fetched_at };
      fillConverterSelects();
      updateConverter();
      fillHistAssetSelect();
      await fetchDashboard();
      detectRateAlerts(prevSnap, liveRates);
    } catch (e) {
      showToast('Не вдалося оновити курси. Перевірте з\'єднання.', 'error');
    }
  }

  function refreshLive() {
    return withButtonSpinner(el.btnRefresh, _doRefreshLive);
  }

  var CHART_COLORS = ['#34d399', '#fbbf24', '#60a5fa', '#f87171', '#a78bfa'];
  var MAX_HIST_ASSETS = 5;

  function getSelectedHistAssets() {
    if (!el.histAsset) return [];
    var selected = [];
    Array.prototype.forEach.call(el.histAsset.options, function (o) {
      if (o.selected) selected.push(o.value);
    });
    return selected;
  }

  function updateHistAssetLabel() {
    var sel = getSelectedHistAssets();
    if (!el.histAssetLabel) return;
    if (sel.length === 0) {
      el.histAssetLabel.textContent = '—';
    } else if (sel.length === 1) {
      var p = parsePairKeyString(sel[0]);
      el.histAssetLabel.textContent = p ? p.sym : sel[0];
    } else {
      el.histAssetLabel.textContent = sel.length + ' активів обрано';
    }
  }

  function fillHistAssetSelect() {
    if (!el.histAsset || !el.histAssetMenu) return;
    var prevSelected = getSelectedHistAssets();
    el.histAsset.innerHTML = '';
    el.histAssetMenu.innerHTML = '';

    var searchLi = document.createElement('li');
    searchLi.className = 'px-2 pb-2 hist-asset-search-wrap';
    var searchInput = document.createElement('input');
    searchInput.type = 'text';
    searchInput.className = 'form-control form-control-sm';
    searchInput.placeholder = 'Пошук активу\u2026';
    searchInput.setAttribute('aria-label', 'Пошук активу');
    searchLi.appendChild(searchInput);
    el.histAssetMenu.appendChild(searchLi);

    searchInput.addEventListener('input', function () {
      var q = this.value.toLowerCase().trim();
      el.histAssetMenu.querySelectorAll('li[data-asset-item]').forEach(function (li) {
        var label = (li.getAttribute('data-search-label') || '').toLowerCase();
        li.style.display = label.indexOf(q) >= 0 ? '' : 'none';
      });
    });
    searchInput.addEventListener('click', function (ev) { ev.stopPropagation(); });
    searchInput.addEventListener('keydown', function (ev) { ev.stopPropagation(); });

    liveRates.forEach(function (r) {
      var value = (r.asset_symbol || '').toUpperCase() + ':' + r.asset_type;
      var symU = (r.asset_symbol || '').toUpperCase();
      var label = symU + ' \u2014 ' + displayName(r) + '  ' + displayIcon(r);
      var opt = new Option(label, value);
      el.histAsset.appendChild(opt);
      var li = document.createElement('li');
      li.setAttribute('data-asset-item', '1');
      li.setAttribute('data-search-label', symU + ' ' + displayName(r));
      var btn = document.createElement('button');
      btn.type = 'button';
      btn.className = 'dropdown-item text-start py-2 d-flex align-items-center gap-2';
      btn.setAttribute('data-value', value);
      var cb = document.createElement('input');
      cb.type = 'checkbox';
      cb.className = 'form-check-input me-0';
      cb.style.pointerEvents = 'none';
      cb.setAttribute('data-cb-value', value);
      btn.appendChild(cb);
      btn.appendChild(document.createTextNode(label));
      li.appendChild(btn);
      el.histAssetMenu.appendChild(li);
    });
    var prefer = st.histDefaultPair;
    if (prevSelected.length) {
      prevSelected.forEach(function (v) {
        var o = el.histAsset.querySelector('option[value="' + v + '"]');
        if (o) o.selected = true;
      });
    } else if (prefer && typeof prefer === 'string') {
      var arr = prefer.indexOf(',') >= 0 ? prefer.split(',') : [prefer];
      arr.forEach(function (v) {
        var o = el.histAsset.querySelector('option[value="' + v.trim() + '"]');
        if (o) o.selected = true;
      });
    }
    if (!getSelectedHistAssets().length && el.histAsset.options.length) {
      el.histAsset.options[0].selected = true;
    }
    syncHistAssetCheckboxes();
    updateHistAssetLabel();
  }

  function syncHistAssetCheckboxes() {
    var sel = new Set(getSelectedHistAssets());
    el.histAssetMenu.querySelectorAll('input[data-cb-value]').forEach(function (cb) {
      cb.checked = sel.has(cb.getAttribute('data-cb-value'));
    });
  }

  function wireHistAssetMultiSelect() {
    if (!el.histAssetMenu || !el.histAsset) return;
    el.histAssetMenu.addEventListener('click', function (ev) {
      var item = ev.target.closest('button[data-value]');
      if (!item || !el.histAssetMenu.contains(item)) return;
      ev.preventDefault();
      ev.stopPropagation();
      var val = item.getAttribute('data-value');
      var opt = el.histAsset.querySelector('option[value="' + val + '"]');
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
      var selected = getSelectedHistAssets();
      st.histDefaultPair = selected.join(',');
      saveState({ histDefaultPair: st.histDefaultPair });
    });
  }

  function buildHistoryTableRowsHtml(items, showAssetCol) {
    return items.map(function (it) {
      if (it._gap) return '';
      var pct = it.pct_change_from_prev;
      var pctCell = pct == null ? '—' : formatPct(pct);
      var dtEsc = escapeHtml(formatLocalDateTime(it.created_at));
      var uahEsc = escapeHtml(formatPrice(it.price_uah));
      var usdEsc = escapeHtml(formatPrice(it.price_usd));
      var pctEsc = escapeHtml(pctCell);
      var tc = trendClass(pct);
      var symCell = showAssetCol ? '<td><strong>' + escapeHtml(it._sym || '') + '</strong></td>' : '';
      return (
        '<tr>' + symCell + '<td>' + dtEsc + '</td>' +
        '<td class="text-end">' + uahEsc + '</td>' +
        '<td class="text-end">' + usdEsc + '</td>' +
        '<td class="text-end ' + tc + '">' + pctEsc + '</td></tr>'
      );
    }).join('');
  }

  function getHistPageSize() {
    return Number(st.histPageSize) || HIST_DEFAULT_PAGE;
  }

  function renderHistoryTable() {
    if (!el.histTbody) return;
    var showAssetCol = _histMultiMode;
    var realItems = _histAllItems.filter(function (it) { return !it._gap; });
    if (!_histMultiMode) realItems = realItems.slice().reverse();
    var pageSize = getHistPageSize();
    var slice = realItems.slice(0, _histShown + pageSize);
    el.histTbody.innerHTML = buildHistoryTableRowsHtml(slice, showAssetCol);
    _histShown = slice.length;

    var thead = el.histTbody.closest('table');
    if (thead) {
      var existingAssetTh = thead.querySelector('th[data-hist-asset-col]');
      var firstTh = thead.querySelector('thead tr th');
      if (showAssetCol && !existingAssetTh && firstTh) {
        var th = document.createElement('th');
        th.setAttribute('scope', 'col');
        th.setAttribute('data-hist-asset-col', '1');
        th.textContent = 'Актив';
        firstTh.parentNode.insertBefore(th, firstTh);
      } else if (!showAssetCol && existingAssetTh) {
        existingAssetTh.remove();
      }
    }

    var remaining = realItems.length - _histShown;
    if (el.histShowMore) {
      if (remaining > 0) {
        el.histShowMore.textContent = 'Показати ще ' + Math.min(remaining, pageSize);
        el.histShowMore.classList.remove('d-none');
      } else {
        el.histShowMore.classList.add('d-none');
      }
    }
  }

  function buildHistQueryString(sym, typ, range) {
    var qParts = ['asset_symbol=' + encodeURIComponent(sym), 'asset_type=' + encodeURIComponent(typ)];
    if (range === 'custom') {
      var dfrom = document.getElementById('hist-date-from');
      var dto = document.getElementById('hist-date-to');
      if (dfrom && dfrom.value) qParts.push('date_from=' + encodeURIComponent(dfrom.value));
      if (dto && dto.value) qParts.push('date_to=' + encodeURIComponent(dto.value));
      qParts.push('range=custom');
    } else {
      qParts.push('range=' + encodeURIComponent(range));
    }
    return qParts.join('&');
  }

  /**
   * Build a unified epoch-based timeline from multiple series.
   * Returns sorted array of unique epoch-ms values.
   */
  function buildUnifiedTimeline(seriesArr) {
    var set = {};
    seriesArr.forEach(function (items) {
      items.forEach(function (it) {
        if (it._gap) return;
        var d = parseTimestamp(it.created_at);
        if (d) set[d.getTime()] = true;
      });
    });
    return Object.keys(set).map(Number).sort(function (a, b) { return a - b; });
  }

  /**
   * Align a single series to the unified timeline.
   * For each timeline epoch, find the nearest data point within `tolerance` ms.
   * Returns array of values (or null for gaps/missing).
   */
  function alignSeriesToTimeline(items, timeline, metric, toleranceMs) {
    var epochMap = [];
    items.forEach(function (it) {
      if (it._gap) { epochMap.push({ epoch: null, val: null }); return; }
      var d = parseTimestamp(it.created_at);
      var val = metric === 'uah' ? it.price_uah : it.price_usd;
      if (d && val != null) epochMap.push({ epoch: d.getTime(), val: Number(val) });
    });
    var sorted = epochMap.filter(function (e) { return e.epoch != null; });
    return timeline.map(function (ts) {
      var best = null;
      var bestDist = Infinity;
      for (var i = 0; i < sorted.length; i++) {
        var dist = Math.abs(sorted[i].epoch - ts);
        if (dist < bestDist) { bestDist = dist; best = sorted[i]; }
        if (sorted[i].epoch > ts) break;
      }
      if (best && bestDist <= toleranceMs) return best.val;
      return null;
    });
  }

  /**
   * Normalize values to % change from first non-null value (baseline = 0%).
   */
  function normalizeToPctChange(values) {
    var base = null;
    for (var i = 0; i < values.length; i++) {
      if (values[i] != null) { base = values[i]; break; }
    }
    if (base == null || base === 0) return values;
    return values.map(function (v) {
      if (v == null) return null;
      return ((v - base) / base) * 100;
    });
  }

  function computeStats(values) {
    var nums = values.filter(function (v) { return v != null && !Number.isNaN(Number(v)); }).map(Number);
    if (!nums.length) return null;
    var sorted = nums.slice().sort(function (a, b) { return a - b; });
    var sum = sorted.reduce(function (s, v) { return s + v; }, 0);
    var mid = Math.floor(sorted.length / 2);
    var median = sorted.length % 2 !== 0 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
    return { min: sorted[0], max: sorted[sorted.length - 1], avg: sum / sorted.length, median: median, count: sorted.length };
  }

  function renderHistStats(parsed, isMulti) {
    var box = document.getElementById('hist-stats');
    if (!box) return;
    if (!parsed || !parsed.length) { box.classList.add('d-none'); box.innerHTML = ''; return; }

    var html = '';
    parsed.forEach(function (p, idx) {
      var vals = (p.items || []).map(function (it) {
        return p.metric === 'uah' ? it.price_uah : it.price_usd;
      });
      var s = computeStats(vals);
      if (!s) return;
      var unit = p.metricLabel || '';
      var color = CHART_COLORS[idx % CHART_COLORS.length];
      if (isMulti) {
        html += '<div class="d-flex flex-wrap gap-2 align-items-center w-100">';
        html += '<span class="hist-stat-group-label"><span class="hist-stat-dot" style="background:' + color + '"></span>' + escapeHtml(p.sym) + ' (' + unit + ')</span>';
      }
      html += '<span class="glass hist-stat-badge">Мін: ' + escapeHtml(formatPrice(s.min)) + '</span>';
      html += '<span class="glass hist-stat-badge">Макс: ' + escapeHtml(formatPrice(s.max)) + '</span>';
      html += '<span class="glass hist-stat-badge">Середнє: ' + escapeHtml(formatPrice(s.avg)) + '</span>';
      html += '<span class="glass hist-stat-badge">Медіана: ' + escapeHtml(formatPrice(s.median)) + '</span>';
      if (isMulti) html += '</div>';
    });
    box.innerHTML = html;
    box.classList.toggle('d-none', !html);
  }

  function _isLight() {
    return document.documentElement.getAttribute('data-theme') === 'light';
  }
  function _chartTheme() {
    if (_isLight()) return {
      text: 'rgba(17,19,24,0.78)',
      tick: 'rgba(17,19,24,0.62)',
      grid: 'rgba(17,19,24,0.08)',
      tooltipText: '#1e2028',
      tooltipBg: 'rgba(255,255,255,0.88)',
      tooltipBorder: 'rgba(0,0,0,0.10)'
    };
    return {
      text: 'rgba(232,234,239,0.92)',
      tick: 'rgba(232,234,239,0.78)',
      grid: 'rgba(255,255,255,0.07)',
      tooltipText: '#e8eaef',
      tooltipBg: 'rgba(15,20,35,0.92)',
      tooltipBorder: 'rgba(255,255,255,0.12)'
    };
  }

  var _histMultiMode = false;
  var _histAbsoluteValues = {};

  async function loadHistorySeries() {
    if (!el.histAsset || !el.histRange) return;
    var selected = getSelectedHistAssets();
    if (!selected.length) return;
    var range = el.histRange.value;
    var isMulti = selected.length > 1;
    _histMultiMode = isMulti;
    saveState({ histRange: range });
    if (el.histChartErr) {
      el.histChartErr.classList.add('d-none');
      el.histChartErr.textContent = '';
    }

    try {
      var fetches = selected.map(function (v) {
        var parts = v.split(':');
        var sym = parts[0];
        var typ = parts[1];
        var q = buildHistQueryString(sym, typ, range);
        return fetchWithRetry('/api/history/series?' + q).then(function (r) { return r.json(); }).then(function (data) {
          return { key: v, sym: sym, typ: typ, data: data };
        });
      });
      var results = await Promise.all(fetches);

      var firstError = results.find(function (r) { return r.data && r.data.error; });
      if (firstError && results.length === 1) {
        if (el.histChartErr) {
          el.histChartErr.textContent = firstError.data.detail || firstError.data.error || 'Помилка';
          el.histChartErr.classList.remove('d-none');
        }
        return;
      }

      var parsed = [];
      var allRawItems = [];
      results.forEach(function (r) {
        var items = (r.data && r.data.items) || [];
        if (!items.length) return;
        var metric = (r.data && r.data.series_metric) || 'uah';
        var chartItems = insertGapMarkers(items);
        items.forEach(function (it) {
          allRawItems.push({ _sym: r.sym, _metric: metric, created_at: it.created_at, price_uah: it.price_uah, price_usd: it.price_usd, pct_change_from_prev: it.pct_change_from_prev });
        });
        parsed.push({ sym: r.sym, metric: metric, metricLabel: metric === 'uah' ? 'UAH' : 'USD', items: items, chartItems: chartItems });
      });

      var hasData = parsed.length > 0;
      if (el.histEmpty) el.histEmpty.classList.toggle('d-none', hasData);
      if (!hasData) {
        _histAllItems = [];
        _histShown = 0;
        if (el.histTbody) el.histTbody.innerHTML = '';
        if (el.histShowMore) el.histShowMore.classList.add('d-none');
        destroyChartInstance(histMainChart);
        histMainChart = null;
        return;
      }

      var datasets;
      var chartLabels;
      var yAxisLabel;
      _histAbsoluteValues = {};

      if (!isMulti) {
        var p = parsed[0];
        var ci = p.chartItems;
        chartLabels = ci.map(function (it) { return formatChartAxisLabel(it.created_at, range); });
        var vals = ci.map(function (it) {
          if (it._gap) return null;
          return p.metric === 'uah' ? it.price_uah : it.price_usd;
        });
        yAxisLabel = p.metricLabel;
        datasets = [{
          label: p.sym + ' (' + p.metricLabel + ')',
          data: vals,
          borderColor: CHART_COLORS[0],
          backgroundColor: CHART_COLORS[0],
          tension: 0.32,
          fill: false,
          spanGaps: false
        }];
      } else {
        var allSeries = parsed.map(function (p) { return p.chartItems; });
        var timeline = buildUnifiedTimeline(allSeries);
        var toleranceMs = 15 * 60 * 1000;
        if (range === '24h') toleranceMs = 5 * 60 * 1000;

        chartLabels = timeline.map(function (epoch) {
          var d = new Date(epoch);
          if (range === '24h') return pad2(d.getHours()) + ':' + pad2(d.getMinutes());
          return pad2(d.getDate()) + '.' + pad2(d.getMonth() + 1) + '.' + d.getFullYear();
        });

        datasets = parsed.map(function (p, idx) {
          var aligned = alignSeriesToTimeline(p.chartItems, timeline, p.metric, toleranceMs);
          _histAbsoluteValues[p.sym] = aligned.slice();
          var normalized = normalizeToPctChange(aligned);
          return {
            label: p.sym + ' (' + p.metricLabel + ')',
            data: normalized,
            borderColor: CHART_COLORS[idx % CHART_COLORS.length],
            backgroundColor: CHART_COLORS[idx % CHART_COLORS.length],
            tension: 0.32,
            fill: false,
            spanGaps: false,
            _sym: p.sym,
            _metricLabel: p.metricLabel
          };
        });
        yAxisLabel = '% зміна';
      }

      var tooltipCallbacks = {};
      if (isMulti) {
        tooltipCallbacks.label = function (ctx) {
          var ds = ctx.dataset;
          var sym = ds._sym || ds.label;
          var ml = ds._metricLabel || '';
          var pct = ctx.parsed.y;
          if (pct == null) return null;
          var absArr = _histAbsoluteValues[sym];
          var absVal = absArr ? absArr[ctx.dataIndex] : null;
          var parts = sym + ': ' + (pct >= 0 ? '+' : '') + pct.toFixed(2) + '%';
          if (absVal != null) parts += '  (' + formatPrice(absVal) + ' ' + ml + ')';
          return parts;
        };
      }

      var ctx = document.getElementById('hist-chart');
      destroyChartInstance(histMainChart);
      histMainChart = new Chart(ctx, {
        type: 'line',
        data: { labels: chartLabels, datasets: datasets },
        options: {
          responsive: true,
          maintainAspectRatio: false,
          interaction: { mode: 'index', intersect: false },
          plugins: {
            legend: {
              display: true,
              labels: { color: _chartTheme().text }
            },
            tooltip: {
              titleColor: _chartTheme().tooltipText,
              bodyColor: _chartTheme().tooltipText,
              backgroundColor: _chartTheme().tooltipBg,
              borderColor: _chartTheme().tooltipBorder,
              borderWidth: 1,
              filter: function (item) { return item.raw != null; },
              callbacks: tooltipCallbacks
            }
          },
          scales: {
            x: {
              grid: { color: _chartTheme().grid },
              ticks: {
                color: _chartTheme().tick,
                autoSkip: true,
                maxTicksLimit: 12,
                maxRotation: 0,
                minRotation: 0
              }
            },
            y: {
              grid: { color: _chartTheme().grid },
              ticks: { color: _chartTheme().tick },
              title: {
                display: !!yAxisLabel,
                text: yAxisLabel || '',
                color: _chartTheme().tick
              }
            }
          }
        }
      });

      if (isMulti) {
        allRawItems.sort(function (a, b) {
          var da = parseTimestamp(a.created_at);
          var db = parseTimestamp(b.created_at);
          if (!da || !db) return 0;
          return db.getTime() - da.getTime();
        });
        _histAllItems = allRawItems;
      } else {
        _histAllItems = parsed[0] ? insertGapMarkers(parsed[0].items) : [];
      }
      _histShown = 0;
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

  /* -------------------------------------------------------------------------- */
  /* Події UI                                                                   */
  /* -------------------------------------------------------------------------- */
  function bindLive() {
    if (el.liveSearch) {
      const onSearch = function () {
        saveState({ liveSearch: el.liveSearch.value });
        renderLive();
      };
      el.liveSearch.addEventListener('input', onSearch);
      el.liveSearch.addEventListener('change', onSearch);
    }
    if (el.liveType && el.liveTypeToggle && el.liveTypeMenu) {
      const onType = function () {
        saveState({ liveType: el.liveType.value });
        renderLive();
      };
      wireCoSelectDropdown(el.liveTypeToggle, el.liveTypeMenu, el.liveType, onType);
      wireCoSelectTypeahead(el.liveTypeToggle, el.liveTypeMenu);
    }
    if (el.liveShowAll) {
      const onShowAll = function () {
        saveState({ liveShowAll: el.liveShowAll.checked });
        renderLive();
      };
      el.liveShowAll.addEventListener('input', onShowAll);
      el.liveShowAll.addEventListener('change', onShowAll);
    }
    // Делегування: один слухач на таблицю — стійкіше до майбутніх змін у thead.
    if (el.liveTable) {
      el.liveTable.addEventListener('click', function (ev) {
        const th = ev.target.closest('th.sortable');
        if (!th || !el.liveTable.contains(th)) return;
        const k = th.getAttribute('data-sort');
        if (!k) return;
        if (liveSort.key === k) liveSort.dir = -liveSort.dir;
        else { liveSort.key = k; liveSort.dir = 1; }
        renderLive();
      });
    }
    if (el.liveTbody) {
      el.liveTbody.addEventListener('click', function (ev) {
        const btn = ev.target.closest('.kpi-star-toggle');
        if (!btn || !el.liveTbody.contains(btn)) return;
        ev.preventDefault();
        const pk = btn.getAttribute('data-pair');
        if (!pk) return;
        toggleFavoritePair(pk);
        renderLive();
      });
    }
    let _convAmtTimer = null;
    if (el.convAmount) {
      el.convAmount.addEventListener('input', function () {
        updateConverter();
        clearTimeout(_convAmtTimer);
        _convAmtTimer = setTimeout(function () {
          saveState({ convAmount: el.convAmount.value });
        }, 300);
      });
    }
    if (el.convFromToggle && el.convFromMenu && el.convFrom) {
      wireCoSelectDropdown(el.convFromToggle, el.convFromMenu, el.convFrom, function () {
        saveState({ convFrom: el.convFrom.value, convTo: el.convTo.value });
        updateConverter();
      });
    }
    if (el.convToToggle && el.convToMenu && el.convTo) {
      wireCoSelectDropdown(el.convToToggle, el.convToMenu, el.convTo, function () {
        saveState({ convFrom: el.convFrom.value, convTo: el.convTo.value });
        updateConverter();
      });
    }
    wireHistAssetMultiSelect();
    wireCoSelectTypeahead(el.convFromToggle, el.convFromMenu);
    wireCoSelectTypeahead(el.convToToggle, el.convToMenu);
    const convSwap = document.getElementById('conv-swap');
    if (convSwap && el.convFrom && el.convTo) {
      convSwap.addEventListener('click', function () {
        const fromVal = el.convFrom.value;
        el.convFrom.value = el.convTo.value;
        el.convTo.value = fromVal;
        syncDropdownLabel(el.convFrom, el.convFromLabel);
        syncDropdownLabel(el.convTo, el.convToLabel);
        saveState({ convFrom: el.convFrom.value, convTo: el.convTo.value });
        updateConverter();
      });
    }
    if (el.btnRefresh) el.btnRefresh.addEventListener('click', refreshLive);
    bindKpiDrag();
  }

  function bindHist() {
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
        var v = parseInt(el.histPageSize.value, 10);
        if (!isNaN(v)) {
          st.histPageSize = v;
          saveState({ histPageSize: v });
        }
        _histShown = 0;
        renderHistoryTable();
      });
    }
    if (el.histRange && el.histRangeToggle && el.histRangeMenu) {
      const onRange = function () {
        saveState({ histRange: el.histRange.value });
        toggleCustomRangeFields();
      };
      wireCoSelectDropdown(el.histRangeToggle, el.histRangeMenu, el.histRange, onRange);
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
        var icon = el.histFullscreen.querySelector('i');
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

  /** Заокруглення панелі вкладок: «Історія» — повний radius; «Поточні курси» — без верхнього лівого (стик з першою вкладкою). */
  function syncTabShellRadius() {
    const shell = document.querySelector('.tab-content.tab-shell');
    const histBtn = document.getElementById('hist-tab');
    if (!shell || !histBtn) return;
    shell.classList.toggle('tab-shell--hist', histBtn.classList.contains('active'));
  }

  function bindMainTabs() {
    ['live-tab', 'hist-tab'].forEach(function (id) {
      const btn = document.getElementById(id);
      if (btn) btn.addEventListener('shown.bs.tab', syncTabShellRadius);
    });
    syncTabShellRadius();
  }

  function initHistPageSizeFilter() {
    if (!el.histPageSize || !el.histPageSizeMenu || !el.histPageSizeLabel) return;
    var defs = HIST_PAGE_SIZES.map(function (n) { return { value: String(n), label: String(n) }; });
    fillHiddenSelectAndMenu(el.histPageSize, el.histPageSizeMenu, defs);
    el.histPageSize.value = String(st.histPageSize || HIST_DEFAULT_PAGE);
    syncDropdownLabel(el.histPageSize, el.histPageSizeLabel);
  }

  function startAutoRefresh() {
    if (_autoRefreshId) clearInterval(_autoRefreshId);
    _autoRefreshId = setInterval(function () {
      if (document.visibilityState !== 'visible') return;
      _doRefreshLive();
    }, AUTO_REFRESH_INTERVAL_MS);
  }

  var THEME_COLORS = { dark: '#080b14', light: '#e4f0ec' };

  function setThemeColorMeta(theme) {
    var meta = document.getElementById('meta-theme-color');
    if (meta) meta.setAttribute('content', THEME_COLORS[theme] || THEME_COLORS.dark);
  }

  function initThemeToggle() {
    var toggle = document.getElementById('theme-toggle');
    var icon = document.getElementById('theme-icon');
    if (!toggle) return;
    var saved = st.theme || 'dark';
    if (saved === 'light') {
      document.documentElement.setAttribute('data-theme', 'light');
      if (icon) { icon.className = 'bi bi-sun-fill'; }
      setThemeColorMeta('light');
    }
    toggle.addEventListener('click', function () {
      var current = document.documentElement.getAttribute('data-theme');
      var next = current === 'light' ? 'dark' : 'light';
      document.documentElement.setAttribute('data-theme', next);
      if (icon) {
        icon.className = next === 'light' ? 'bi bi-sun-fill' : 'bi bi-moon-stars';
      }
      setThemeColorMeta(next);
      st.theme = next;
      saveState({ theme: next });
    });
  }

  initThemeToggle();
  initLiveTypeFilter();
  initHistRangeFilter();
  initHistPageSizeFilter();
  bindLive();
  bindHist();
  bindMainTabs();
  fillConverterSelects();
  updateConverter();
  fillHistAssetSelect();
  updateKpis();
  renderLive();
  fetchDashboard();
  initTooltips();
  startRelativeTimeTicker();
  startAutoRefresh();
})();
