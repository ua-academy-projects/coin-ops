/**
 * CoinOps dashboard: live rates, converter, history chart (Chart.js, Bootstrap markup).
 * Завантажується після chart.umd.min.js; очікує JSON у #coinops-initial-live та #coinops-live-meta.
 */
(function () {
  if (!document.getElementById('live-tbody')) {
    return;
  }
  const POPULAR_FIAT = ['USD', 'EUR', 'GBP', 'PLN', 'CHF', 'CAD'];
  const POPULAR_CRYPTO = ['BTC', 'ETH', 'USDT', 'BNB', 'SOL', 'XRP'];
  const LS_KEY = 'coinops_ui_v2';

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
    return (r.asset_symbol || '').toUpperCase() + ':' + (r.asset_type || '');
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
  }

  /* --- Початкові дані з сервера (JSON у <script type="application/json">) --- */
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
      'Не вдалося розібрати вбудований JSON на сторінці (' + parseProblems.join(', ') + '). Спробуйте оновити сторінку.'
    );
  }

  let liveRates = Array.isArray(initialLive) ? initialLive.slice() : [];
  let dashboardInsights = {};
  let liveSort = { key: 'symbol', dir: 1 };
  let sparkCharts = {};

  const st = loadState();
  const el = {
    liveSearch: document.getElementById('live-search'),
    liveType: document.getElementById('live-type-filter'),
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
    convResult: document.getElementById('converter-result'),
    histAsset: document.getElementById('hist-asset'),
    histRange: document.getElementById('hist-range'),
    histLoad: document.getElementById('hist-load'),
    histTbody: document.getElementById('hist-tbody'),
    histEmpty: document.getElementById('hist-empty'),
    histChartErr: document.getElementById('hist-chart-error'),
  };

  if (el.liveSearch) { el.liveSearch.value = st.liveSearch || ''; }
  if (el.liveType) { el.liveType.value = st.liveType || 'all'; }
  if (el.liveShowAll) { el.liveShowAll.checked = !!st.liveShowAll; }
  if (el.histRange) { el.histRange.value = st.histRange || '7d'; }

  let histMainChart = null;

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
    const usd = findRate('USD', 'fiat');
    const eur = findRate('EUR', 'fiat');
    const btc = findRate('BTC', 'crypto');
    if (el.kpiUsdUah) el.kpiUsdUah.textContent = usd && usd.price_uah != null ? `${formatPrice(usd.price_uah)} UAH` : '—';
    if (el.kpiEurUah) el.kpiEurUah.textContent = eur && eur.price_uah != null ? `${formatPrice(eur.price_uah)} UAH` : '—';
    if (el.kpiBtcUsd) el.kpiBtcUsd.textContent = btc && btc.price_usd != null ? `${formatPrice(btc.price_usd)} USD` : '—';

    function setKpiTrend(trendEl, sym, typ) {
      if (!trendEl) return;
      const it = dashboardInsights[`${sym}:${typ}`];
      const p = it && it.trend_24h_pct;
      trendEl.className = `small mt-auto ${trendClass(p)}`;
      trendEl.textContent = `24 год: ${formatPct(p)}`;
    }
    setKpiTrend(el.kpiUsdTrend, 'USD', 'fiat');
    setKpiTrend(el.kpiEurTrend, 'EUR', 'fiat');
    setKpiTrend(el.kpiBtcTrend, 'BTC', 'crypto');
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

  function cmpLive(a, b) {
    const k = liveSort.key;
    let va, vb;
    if (k === 'symbol') { va = (a.asset_symbol || '').toUpperCase(); vb = (b.asset_symbol || '').toUpperCase(); }
    else if (k === 'uah') { va = a.price_uah != null ? Number(a.price_uah) : -Infinity; vb = b.price_uah != null ? Number(b.price_uah) : -Infinity; }
    else if (k === 'usd') { va = a.price_usd != null ? Number(a.price_usd) : -Infinity; vb = b.price_usd != null ? Number(b.price_usd) : -Infinity; }
    else { va = 0; vb = 0; }
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

  /* --- Рендер DOM (таблиці, KPI після фільтрації) --- */
  function renderLive() {
    if (!el.liveTbody) return;
    destroySparkCharts();
    let rows = filterLiveRows();
    rows = rows.slice().sort(cmpLive);
    // Один запис innerHTML у tbody зменшує reflow; escapeHtml на полях з API.
    const sparkJobs = [];
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
      return (
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
    if (!el.convFrom || !el.convTo) return;
    const syms = buildConverterSymbols();
    el.convFrom.innerHTML = '';
    el.convTo.innerHTML = '';
    syms.forEach(function (s) {
      el.convFrom.appendChild(new Option(s, s));
      el.convTo.appendChild(new Option(s, s));
    });
    if (syms.includes('USD')) el.convFrom.value = 'USD';
    if (syms.includes('UAH')) el.convTo.value = 'UAH';
    else if (syms.length > 1) el.convTo.value = syms[1];
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

  /* --- HTTP: зведення для live-дашборду та оновлення курсів --- */
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
    if (!el.histAsset) return;
    const cur = el.histAsset.value;
    el.histAsset.innerHTML = '';
    liveRates.forEach(function (r) {
      const value = `${(r.asset_symbol || '').toUpperCase()}:${r.asset_type}`;
      const label = `${displayIcon(r)} ${r.asset_symbol || ''} — ${displayName(r)}`;
      el.histAsset.appendChild(new Option(label, value));
    });
    if (cur && Array.prototype.some.call(el.histAsset.options, function (o) { return o.value === cur; })) {
      el.histAsset.value = cur;
    } else if (el.histAsset.options.length) {
      el.histAsset.selectedIndex = 0;
    }
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
      // Одна заміна innerHTML; підписи дат з API проходять через escapeHtml.
      if (el.histTbody) {
        el.histTbody.innerHTML = items.map(function (it) {
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
    } catch (err) {
      if (el.histChartErr) {
        el.histChartErr.textContent = 'Не вдалося завантажити історію.';
        el.histChartErr.classList.remove('d-none');
      }
    }
  }

  function bindLive() {
    if (el.liveSearch) {
      const onSearch = function () {
        saveState({ liveSearch: el.liveSearch.value });
        renderLive();
      };
      el.liveSearch.addEventListener('input', onSearch);
      el.liveSearch.addEventListener('change', onSearch);
    }
    if (el.liveType) {
      const onType = function () {
        saveState({ liveType: el.liveType.value });
        renderLive();
      };
      el.liveType.addEventListener('input', onType);
      el.liveType.addEventListener('change', onType);
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
    if (el.convAmount) el.convAmount.addEventListener('input', updateConverter);
    if (el.convFrom) el.convFrom.addEventListener('change', updateConverter);
    if (el.convTo) el.convTo.addEventListener('change', updateConverter);
    const convSwap = document.getElementById('conv-swap');
    if (convSwap && el.convFrom && el.convTo) {
      convSwap.addEventListener('click', function () {
        const fromVal = el.convFrom.value;
        el.convFrom.value = el.convTo.value;
        el.convTo.value = fromVal;
        updateConverter();
      });
    }
    if (el.btnRefresh) el.btnRefresh.addEventListener('click', refreshLive);
  }

  function bindHist() {
    if (el.histLoad) el.histLoad.addEventListener('click', loadHistorySeries);
    if (el.histRange) el.histRange.addEventListener('change', function () { saveState({ histRange: el.histRange.value }); });
    const histTab = document.getElementById('hist-tab');
    if (histTab) {
      histTab.addEventListener('shown.bs.tab', function () {
        fillHistAssetSelect();
        if (el.histAsset && el.histAsset.value) loadHistorySeries();
      });
    }
  }

  bindLive();
  bindHist();
  fillConverterSelects();
  updateConverter();
  fillHistAssetSelect();
  updateKpis();
  renderLive();
  fetchDashboard();
})();
