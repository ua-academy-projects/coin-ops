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
  function formatPrice(v) {
    if (v === null || v === undefined) return '—';
    const n = Number(v);
    if (Number.isNaN(n)) return '—';
    return n.toFixed(2);
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

  function initHistRangeFilter() {
    if (!el.histRange || !el.histRangeMenu || !el.histRangeLabel) return;
    const defs = [
      { value: '24h', label: '24 години' },
      { value: '7d', label: '7 днів' },
      { value: '30d', label: '1 місяць' },
      { value: 'all', label: 'Увесь час' }
    ];
    fillHiddenSelectAndMenu(el.histRange, el.histRangeMenu, defs);
    const saved = st.histRange || '7d';
    const allowed = new Set(defs.map(function (d) { return d.value; }));
    el.histRange.value = allowed.has(saved) ? saved : '7d';
    syncDropdownLabel(el.histRange, el.histRangeLabel);
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
      if (valEls[i]) {
        if (!r) {
          valEls[i].textContent = '—';
        } else if (r.asset_type === 'fiat' && r.price_uah != null) {
          valEls[i].textContent = `${formatPrice(r.price_uah)} UAH`;
        } else if (r.asset_type === 'crypto' && r.price_usd != null) {
          valEls[i].textContent = `${formatPrice(r.price_usd)} USD`;
        } else {
          valEls[i].textContent = '—';
        }
      }
      if (trendEls[i]) {
        const pkTrend = r ? pairKey(r) : '';
        const ins = pkTrend ? dashboardInsights[pkTrend] : null;
        const p = ins && ins.trend_24h_pct;
        trendEls[i].className = `small mt-auto ${trendClass(p)}`;
        trendEls[i].textContent = `24 год: ${formatPct(p)}`;
      }
    }
    if (el.kpiTime) el.kpiTime.textContent = formatLocalDateTime(liveMeta.fetched_at);
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
    el.liveTbody.innerHTML = rowHtmls.map(function (cells) { return `<tr>${cells}</tr>`; }).join('');
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
      const res = await fetch(`/api/history/dashboard?pairs=${encodeURIComponent(pairs)}`);
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

  async function refreshLive() {
    try {
      const res = await fetch('/api/live');
      const data = await res.json();
      if (data.error) return;
      liveRates = Array.isArray(data.rates) ? data.rates.slice() : [];
      liveMeta = { fetched_at: data.fetched_at };
      fillConverterSelects();
      updateConverter();
      fillHistAssetSelect();
      await fetchDashboard();
    } catch (e) {
      /* мережа / JSON — залишаємо поточний стан без змін */
    }
  }

  function fillHistAssetSelect() {
    if (!el.histAsset || !el.histAssetMenu) return;
    const cur = el.histAsset.value;
    el.histAsset.innerHTML = '';
    el.histAssetMenu.innerHTML = '';
    liveRates.forEach(function (r) {
      const value = `${(r.asset_symbol || '').toUpperCase()}:${r.asset_type}`;
      const symU = (r.asset_symbol || '').toUpperCase();
      const label = `${symU} — ${displayName(r)}  ${displayIcon(r)}`;
      el.histAsset.appendChild(new Option(label, value));
      el.histAssetMenu.appendChild(createDropdownMenuItem(value, label, 'dropdown-item text-start py-2'));
    });
    const prefer = st.histDefaultPair && typeof st.histDefaultPair === 'string' ? st.histDefaultPair : null;
    if (prefer && Array.prototype.some.call(el.histAsset.options, function (o) { return o.value === prefer; })) {
      el.histAsset.value = prefer;
    } else if (cur && Array.prototype.some.call(el.histAsset.options, function (o) { return o.value === cur; })) {
      el.histAsset.value = cur;
    } else if (el.histAsset.options.length) {
      el.histAsset.selectedIndex = 0;
    }
    syncDropdownLabel(el.histAsset, el.histAssetLabel);
  }

  /** HTML рядків таблиці історії (лише розмітка; дані з API екрануються). */
  function buildHistoryTableRowsHtml(items) {
    return items.map(function (it) {
      const pct = it.pct_change_from_prev;
      const pctCell = pct == null ? '—' : formatPct(pct);
      const dtEsc = escapeHtml(formatLocalDateTime(it.created_at));
      const uahEsc = escapeHtml(formatPrice(it.price_uah));
      const usdEsc = escapeHtml(formatPrice(it.price_usd));
      const pctEsc = escapeHtml(pctCell);
      const tc = trendClass(pct);
      return (
        `<tr><td>${dtEsc}</td>` +
        `<td class="text-end">${uahEsc}</td>` +
        `<td class="text-end">${usdEsc}</td>` +
        `<td class="text-end ${tc}">${pctEsc}</td></tr>`
      );
    }).join('');
  }

  async function loadHistorySeries() {
    if (!el.histAsset || !el.histRange) return;
    const v = el.histAsset.value;
    if (!v || !v.includes(':')) return;
    const [sym, typ] = v.split(':');
    const range = el.histRange.value;
    saveState({ histRange: range });
    if (el.histChartErr) {
      el.histChartErr.classList.add('d-none');
      el.histChartErr.textContent = '';
    }
    const q = `asset_symbol=${encodeURIComponent(sym)}&asset_type=${encodeURIComponent(typ)}&range=${encodeURIComponent(range)}`;
    try {
      const res = await fetch(`/api/history/series?${q}`);
      const data = await res.json();
      if (data.error) {
        if (el.histChartErr) {
          el.histChartErr.textContent = data.detail || data.error || 'Помилка';
          el.histChartErr.classList.remove('d-none');
        }
        return;
      }
      const items = data.items || [];
      if (el.histEmpty) el.histEmpty.classList.toggle('d-none', items.length > 0);
      if (!items.length) {
        if (el.histTbody) el.histTbody.innerHTML = '';
        destroyChartInstance(histMainChart);
        histMainChart = null;
        return;
      }
      const metric = data.series_metric || 'uah';
      const labels = items.map(function (it) { return formatChartAxisLabel(it.created_at, range); });
      const seriesData = items.map(function (it) {
        return metric === 'uah' ? it.price_uah : it.price_usd;
      });
      const ctx = document.getElementById('hist-chart');
      destroyChartInstance(histMainChart);
      histMainChart = new Chart(ctx, {
        type: 'line',
        data: {
          labels: labels,
          datasets: [{
            label: metric === 'uah' ? 'UAH' : 'USD',
            data: seriesData,
            borderColor: '#6ea8fe',
            tension: 0.32,
            fill: false
          }]
        },
        options: {
          responsive: true,
          maintainAspectRatio: false,
          interaction: { mode: 'index', intersect: false },
          plugins: {
            legend: {
              display: true,
              labels: { color: 'rgba(232,234,239,0.85)' }
            },
            tooltip: {
              titleColor: '#e8eaef',
              bodyColor: '#e8eaef',
              backgroundColor: 'rgba(15, 20, 35, 0.92)',
              borderColor: 'rgba(255,255,255,0.12)',
              borderWidth: 1
            }
          },
          scales: {
            x: {
              grid: { color: 'rgba(255,255,255,0.08)' },
              ticks: {
                color: 'rgba(232,234,239,0.65)',
                autoSkip: true,
                maxTicksLimit: 12,
                maxRotation: 0,
                minRotation: 0
              }
            },
            y: {
              grid: { color: 'rgba(255,255,255,0.08)' },
              ticks: { color: 'rgba(232,234,239,0.65)' }
            }
          }
        }
      });
      if (el.histTbody) {
        el.histTbody.innerHTML = buildHistoryTableRowsHtml(items);
      }
    } catch (err) {
      if (el.histChartErr) {
        el.histChartErr.textContent = 'Не вдалося завантажити історію.';
        el.histChartErr.classList.remove('d-none');
      }
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
    wireCoSelectDropdown(el.histAssetToggle, el.histAssetMenu, el.histAsset, function () {
      const v = el.histAsset && el.histAsset.value;
      if (!v) return;
      st.histDefaultPair = v;
      saveState({ histDefaultPair: v });
    });
    wireCoSelectTypeahead(el.convFromToggle, el.convFromMenu);
    wireCoSelectTypeahead(el.convToToggle, el.convToMenu);
    wireCoSelectTypeahead(el.histAssetToggle, el.histAssetMenu);
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
    if (el.histLoad) el.histLoad.addEventListener('click', loadHistorySeries);
    if (el.histRange && el.histRangeToggle && el.histRangeMenu) {
      const onRange = function () {
        saveState({ histRange: el.histRange.value });
      };
      wireCoSelectDropdown(el.histRangeToggle, el.histRangeMenu, el.histRange, onRange);
      wireCoSelectTypeahead(el.histRangeToggle, el.histRangeMenu);
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

  initLiveTypeFilter();
  initHistRangeFilter();
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
})();
