/**
 * CoinOps dashboard — entry point (ES module).
 *
 * Imports feature modules and wires initialisation + event binding.
 * Loaded via <script type="module"> after Chart.js and Bootstrap.
 */

import { AUTO_REFRESH_INTERVAL_MS, RATE_CHANGE_THRESHOLD_PCT } from './modules/constants.js';
import { store, saveState, initStateFromServer }               from './modules/state.js';
import { parseTimestamp, formatRelativeTime, formatLocalDateTime, pairKey } from './modules/formatting.js';
import { fetchWithRetry, withButtonSpinner }                   from './modules/api.js';
import { wireCoSelectDropdown, wireCoSelectTypeahead, syncDropdownLabel } from './modules/dropdowns.js';
import { showToast }       from './modules/toasts.js';
import { initThemeToggle } from './modules/theme.js';
import {
  renderLive, updateKpis, initLiveTypeFilter, liveSort,
  toggleFavoritePair, bindKpiDrag, snapshotKpiRates,
  getKpiSlotPairKeys, rowForPairKey, buildPairsParam
} from './modules/live.js';
import { fillConverterSelects, updateConverter } from './modules/converter.js';
import {
  fillHistAssetSelect, wireHistAssetMultiSelect,
  initHistRangeFilter, initHistPageSizeFilter,
  loadHistorySeries, bindHistEvents
} from './modules/history.js';

/* ---- Bootstrap tooltips ---- */
function initTooltips() {
  if (typeof bootstrap === 'undefined' || !bootstrap.Tooltip) return;
  document.querySelectorAll('[data-bs-toggle="tooltip"]').forEach(function (node) {
    new bootstrap.Tooltip(node);
  });
}

/* ---- Early exit when live panel absent (SSR error page) ---- */
if (!document.getElementById('live-tbody')) {
  initTooltips();
} else {

/* ---- Parse embedded JSON from Jinja ---- */
function parseEmbeddedData() {
  const liveJsonEl = document.getElementById('coinops-initial-live');
  const metaJsonEl = document.getElementById('coinops-live-meta');
  const clientErrEl = document.getElementById('coinops-client-error');
  const problems = [];

  let initialLive = [];
  try {
    const raw = (liveJsonEl && liveJsonEl.textContent) ? liveJsonEl.textContent.trim() : '[]';
    initialLive = JSON.parse(raw || '[]');
  } catch (e) { problems.push('початкові курси'); }
  if (!Array.isArray(initialLive)) { problems.push('поле курсів не є масивом'); initialLive = []; }

  let liveMeta = {};
  try {
    const raw = (metaJsonEl && metaJsonEl.textContent) ? metaJsonEl.textContent.trim() : '{}';
    liveMeta = JSON.parse(raw || '{}');
  } catch (e) { problems.push('метадані оновлення'); }

  if (problems.length && clientErrEl) {
    clientErrEl.textContent =
      `Не вдалося розібрати вбудований JSON на сторінці (${problems.join(', ')}). Спробуйте оновити сторінку.`;
    clientErrEl.classList.remove('d-none');
  }
  return { liveRates: initialLive, liveMeta };
}

const embedded      = parseEmbeddedData();
store.liveRates     = Array.isArray(embedded.liveRates) ? embedded.liveRates.slice() : [];
store.liveMeta      = embedded.liveMeta;

/* ---- Load persisted UI state (localStorage + server + hash) ---- */
await initStateFromServer();

/* ---- Populate DOM references ---- */
store.el = {
  liveSearch:        document.getElementById('live-search'),
  liveType:          document.getElementById('live-type-filter'),
  liveTypeMenu:      document.getElementById('live-type-menu'),
  liveTypeToggle:    document.getElementById('live-type-toggle'),
  liveTypeLabel:     document.getElementById('live-type-label'),
  liveShowAll:       document.getElementById('live-show-all'),
  liveTbody:         document.getElementById('live-tbody'),
  liveTable:         document.getElementById('live-table'),
  kpiUsdUah:         document.getElementById('kpi-usd-uah'),
  kpiEurUah:         document.getElementById('kpi-eur-uah'),
  kpiBtcUsd:         document.getElementById('kpi-btc-usd'),
  kpiUsdTrend:       document.getElementById('kpi-usd-trend'),
  kpiEurTrend:       document.getElementById('kpi-eur-trend'),
  kpiBtcTrend:       document.getElementById('kpi-btc-trend'),
  kpiTime:           document.getElementById('kpi-live-time'),
  btnRefresh:        document.getElementById('btn-refresh-live'),
  convAmount:        document.getElementById('conv-amount'),
  convFrom:          document.getElementById('conv-from'),
  convTo:            document.getElementById('conv-to'),
  convFromMenu:      document.getElementById('conv-from-menu'),
  convToMenu:        document.getElementById('conv-to-menu'),
  convFromToggle:    document.getElementById('conv-from-toggle'),
  convToToggle:      document.getElementById('conv-to-toggle'),
  convFromLabel:     document.getElementById('conv-from-label'),
  convToLabel:       document.getElementById('conv-to-label'),
  convResult:        document.getElementById('converter-result'),
  histAsset:         document.getElementById('hist-asset'),
  histAssetMenu:     document.getElementById('hist-asset-menu'),
  histAssetToggle:   document.getElementById('hist-asset-toggle'),
  histAssetLabel:    document.getElementById('hist-asset-label'),
  histRange:         document.getElementById('hist-range'),
  histRangeMenu:     document.getElementById('hist-range-menu'),
  histRangeToggle:   document.getElementById('hist-range-toggle'),
  histRangeLabel:    document.getElementById('hist-range-label'),
  histLoad:          document.getElementById('hist-load'),
  histTbody:         document.getElementById('hist-tbody'),
  histEmpty:         document.getElementById('hist-empty'),
  histChartErr:      document.getElementById('hist-chart-error'),
  histChartWrap:     document.getElementById('hist-chart-wrap'),
  histFullscreen:    document.getElementById('hist-fullscreen'),
  histShowMore:      document.getElementById('hist-show-more'),
  histPageSizeMenu:  document.getElementById('hist-page-size-menu'),
  histPageSizeToggle:document.getElementById('hist-page-size-toggle'),
  histPageSizeLabel: document.getElementById('hist-page-size-label'),
  histPageSize:      document.getElementById('hist-page-size'),
  liveEmpty:         document.getElementById('live-empty'),
};

/* ---- Apply saved state to DOM ---- */
const { el, st } = store;
if (el.liveSearch) el.liveSearch.value = st.liveSearch || '';
if (el.liveShowAll) el.liveShowAll.checked = !!st.liveShowAll;
if (el.convAmount && st.convAmount != null && st.convAmount !== '') {
  el.convAmount.value = st.convAmount;
}

/* ---- Dashboard fetch (live trends + sparklines) ---- */
async function fetchDashboard() {
  const pairs = buildPairsParam();
  if (!pairs) { store.dashboardInsights = {}; renderLive(); return; }
  try {
    const res  = await fetchWithRetry(`/api/history/dashboard?pairs=${encodeURIComponent(pairs)}`);
    const data = await res.json();
    store.dashboardInsights = {};
    if (data.items && Array.isArray(data.items)) {
      data.items.forEach(function (it) { store.dashboardInsights[pairKey(it)] = it; });
    }
  } catch (e) { store.dashboardInsights = {}; }
  renderLive();
}

/* ---- Rate-change alerts ---- */
function detectRateAlerts(oldRates) {
  if (!oldRates || !Object.keys(oldRates).length) return;
  const keys = getKpiSlotPairKeys();
  keys.forEach(function (pk) {
    const oldVal = oldRates[pk];
    const newRow = rowForPairKey(pk);
    if (!newRow || oldVal == null) return;
    const newVal = newRow.asset_type === 'fiat' ? Number(newRow.price_uah) : Number(newRow.price_usd);
    if (!newVal || Number.isNaN(newVal) || Number.isNaN(oldVal)) return;
    const pctChange = ((newVal - oldVal) / oldVal) * 100;
    if (Math.abs(pctChange) >= RATE_CHANGE_THRESHOLD_PCT) {
      const sym   = (newRow.asset_symbol || '').toUpperCase();
      const arrow = pctChange > 0 ? '\u2191' : '\u2193';
      const sign  = pctChange > 0 ? '+' : '';
      showToast(sym + ' ' + arrow + ' ' + sign + pctChange.toFixed(2) + '%', pctChange > 0 ? 'success' : 'warning');
    }
  });
}

/* ---- Live refresh orchestration ---- */
async function doRefreshLive() {
  const prevSnap = snapshotKpiRates();
  try {
    const res  = await fetchWithRetry('/api/live');
    const data = await res.json();
    if (data.error) return;
    store.liveRates = Array.isArray(data.rates) ? data.rates.slice() : [];
    store.liveMeta  = { fetched_at: data.fetched_at };
    fillConverterSelects();
    updateConverter();
    fillHistAssetSelect();
    await fetchDashboard();
    detectRateAlerts(prevSnap);
  } catch (e) {
    showToast('Не вдалося оновити курси. Перевірте з\'єднання.', 'error');
  }
}

function refreshLive() {
  return withButtonSpinner(el.btnRefresh, doRefreshLive);
}

/* ---- Relative-time ticker ---- */
let relativeTimeId = null;
function startRelativeTimeTicker() {
  if (relativeTimeId) clearInterval(relativeTimeId);
  relativeTimeId = setInterval(function () {
    if (!store.lastFetchedDate || !el.kpiTime) return;
    el.kpiTime.textContent = formatRelativeTime(store.lastFetchedDate);
    el.kpiTime.title = formatLocalDateTime(store.liveMeta.fetched_at);
  }, 1000);
}

/* ---- Auto-refresh ---- */
let autoRefreshId = null;
function startAutoRefresh() {
  if (autoRefreshId) clearInterval(autoRefreshId);
  autoRefreshId = setInterval(function () {
    if (document.visibilityState !== 'visible') return;
    doRefreshLive();
  }, AUTO_REFRESH_INTERVAL_MS);
}

/* ---- Tab shell radius sync ---- */
function syncTabShellRadius() {
  const shell   = document.querySelector('.tab-content.tab-shell');
  const histBtn = document.getElementById('hist-tab');
  if (!shell || !histBtn) return;
  shell.classList.toggle('tab-shell--hist', histBtn.classList.contains('active'));
}

/* ---- Event binding: live tab ---- */
function bindLiveEvents() {
  if (el.liveSearch) {
    const onSearch = function () { saveState({ liveSearch: el.liveSearch.value }); renderLive(); };
    el.liveSearch.addEventListener('input',  onSearch);
    el.liveSearch.addEventListener('change', onSearch);
  }
  if (el.liveType && el.liveTypeToggle && el.liveTypeMenu) {
    wireCoSelectDropdown(el.liveTypeToggle, el.liveTypeMenu, el.liveType, function () {
      saveState({ liveType: el.liveType.value }); renderLive();
    });
    wireCoSelectTypeahead(el.liveTypeToggle, el.liveTypeMenu);
  }
  if (el.liveShowAll) {
    const onShowAll = function () { saveState({ liveShowAll: el.liveShowAll.checked }); renderLive(); };
    el.liveShowAll.addEventListener('input',  onShowAll);
    el.liveShowAll.addEventListener('change', onShowAll);
  }
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
      if (pk) { toggleFavoritePair(pk); renderLive(); }
    });
  }
}

/* ---- Event binding: converter ---- */
function bindConverterEvents() {
  let convAmtTimer = null;
  if (el.convAmount) {
    el.convAmount.addEventListener('input', function () {
      updateConverter();
      clearTimeout(convAmtTimer);
      convAmtTimer = setTimeout(function () { saveState({ convAmount: el.convAmount.value }); }, 300);
    });
  }
  if (el.convFromToggle && el.convFromMenu && el.convFrom) {
    wireCoSelectDropdown(el.convFromToggle, el.convFromMenu, el.convFrom, function () {
      saveState({ convFrom: el.convFrom.value, convTo: el.convTo.value }); updateConverter();
    });
  }
  if (el.convToToggle && el.convToMenu && el.convTo) {
    wireCoSelectDropdown(el.convToToggle, el.convToMenu, el.convTo, function () {
      saveState({ convFrom: el.convFrom.value, convTo: el.convTo.value }); updateConverter();
    });
  }
  wireCoSelectTypeahead(el.convFromToggle, el.convFromMenu);
  wireCoSelectTypeahead(el.convToToggle,   el.convToMenu);
  const convSwap = document.getElementById('conv-swap');
  if (convSwap && el.convFrom && el.convTo) {
    convSwap.addEventListener('click', function () {
      const fromVal = el.convFrom.value;
      el.convFrom.value = el.convTo.value;
      el.convTo.value   = fromVal;
      syncDropdownLabel(el.convFrom, el.convFromLabel);
      syncDropdownLabel(el.convTo,   el.convToLabel);
      saveState({ convFrom: el.convFrom.value, convTo: el.convTo.value });
      updateConverter();
    });
  }
  if (el.btnRefresh) el.btnRefresh.addEventListener('click', refreshLive);
}

/* ---- Event binding: main tabs ---- */
function bindMainTabs() {
  ['live-tab', 'hist-tab'].forEach(function (id) {
    const btn = document.getElementById(id);
    if (btn) btn.addEventListener('shown.bs.tab', syncTabShellRadius);
  });
  syncTabShellRadius();
}

/* ---- Initialisation sequence ---- */
initThemeToggle();
initLiveTypeFilter();
initHistRangeFilter();
initHistPageSizeFilter();
bindLiveEvents();
bindConverterEvents();
wireHistAssetMultiSelect();
bindHistEvents();
bindMainTabs();
bindKpiDrag();
fillConverterSelects();
updateConverter();
fillHistAssetSelect();
updateKpis();
renderLive();
fetchDashboard();
initTooltips();
startRelativeTimeTicker();
startAutoRefresh();

/* ---- Pause heavy animations while page hidden ---- */
document.addEventListener('visibilitychange', function () {
  if (document.hidden) {
    document.body.classList.add('page-hidden');
    if (relativeTimeId) { clearInterval(relativeTimeId); relativeTimeId = null; }
  } else {
    document.body.classList.remove('page-hidden');
    startRelativeTimeTicker();
  }
});

} // end else (live-tbody present)
