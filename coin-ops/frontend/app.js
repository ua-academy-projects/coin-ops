'use strict';

const API_BASE = '';   // empty = same origin (nginx proxies /api/ to backend)

const CHART_COLORS = [
  '#6366f1', '#22c55e', '#f59e0b',
  '#ef4444', '#3b82f6', '#a855f7',
  '#06b6d4', '#ec4899',
];

let currencies = [];      // [{currency_code, currency_name, source, base_currency}]
let panelCount  = 0;
const charts    = {};     // panelId → Chart instance

// ── Bootstrap ─────────────────────────────────────────────────────────────────

document.addEventListener('DOMContentLoaded', async () => {
  setupTabs();

  document.getElementById('btn-refresh').addEventListener('click', refreshRates);
  document.getElementById('btn-add-chart').addEventListener('click', addChartPanel);

  await loadCurrencies();
  await refreshRates();
  addChartPanel();            // one default chart on load
});

// ── Tabs ───────────────────────────────────────────────────────────────────────

function setupTabs() {
  document.querySelectorAll('.tab-btn').forEach(btn => {
    btn.addEventListener('click', () => {
      document.querySelectorAll('.tab-btn, .tab-content').forEach(el => {
        el.classList.remove('active');
      });
      btn.classList.add('active');
      document.getElementById(`tab-${btn.dataset.tab}`).classList.add('active');
    });
  });
}

// ── Currencies ─────────────────────────────────────────────────────────────────

async function loadCurrencies() {
  try {
    const res = await fetch(`${API_BASE}/api/currencies`);
    if (!res.ok) throw new Error(res.statusText);
    currencies = await res.json();
    setStatus(true);
  } catch (e) {
    setStatus(false);
    console.error('[loadCurrencies]', e);
  }
}

// ── Current Rates Table ────────────────────────────────────────────────────────

async function refreshRates() {
  const tbody = document.getElementById('rates-body');
  try {
    const res = await fetch(`${API_BASE}/api/rates/latest`);
    if (!res.ok) throw new Error(res.statusText);
    const rows = await res.json();
    renderTable(rows);
    setStatus(true);
  } catch (e) {
    tbody.innerHTML = `<tr><td colspan="6" class="err-msg">Could not load rates — ${e.message}</td></tr>`;
    setStatus(false);
  }
}

function renderTable(rows) {
  const tbody = document.getElementById('rates-body');

  if (!rows.length) {
    tbody.innerHTML = `<tr><td colspan="6" class="empty-msg">No data yet — waiting for the first API fetch.</td></tr>`;
    return;
  }

  rows.sort((a, b) => {
    if (a.source !== b.source) return a.source < b.source ? -1 : 1;
    return a.currency_code < b.currency_code ? -1 : 1;
  });

  tbody.innerHTML = rows.map(r => `
    <tr>
      <td><span class="badge badge-${r.source}">${r.source.toUpperCase()}</span></td>
      <td><strong>${r.currency_code}</strong></td>
      <td>${r.currency_name || '—'}</td>
      <td class="rate-val">${fmtRate(r.rate)}</td>
      <td>${r.base_currency}</td>
      <td class="ts">${fmtTime(r.fetched_at)}</td>
    </tr>
  `).join('');
}

// ── Chart Panels ───────────────────────────────────────────────────────────────

function addChartPanel() {
  panelCount++;
  const id = `panel-${panelCount}`;

  const panel = document.createElement('div');
  panel.className = 'chart-panel';
  panel.id = id;
  panel.innerHTML = `
    <div class="panel-header">
      <div class="panel-controls">
        <select class="currency-select">
          <option value="">— Select currency pair —</option>
          ${buildOptions()}
        </select>
        <select class="limit-select">
          <option value="50">Last 50 points</option>
          <option value="100" selected>Last 100 points</option>
          <option value="200">Last 200 points</option>
          <option value="500">Last 500 points</option>
        </select>
      </div>
      <button class="btn-remove">✕ Remove</button>
    </div>
    <div class="chart-wrapper">
      <canvas id="canvas-${id}"></canvas>
    </div>
  `;

  document.getElementById('charts-container').appendChild(panel);

  panel.querySelector('.currency-select').addEventListener('change', () => loadChart(id));
  panel.querySelector('.limit-select').addEventListener('change',   () => loadChart(id));
  panel.querySelector('.btn-remove').addEventListener('click', () => removePanel(id));
}

function buildOptions() {
  if (!currencies.length) return '<option disabled>No data yet</option>';

  const bySrc = {};
  currencies.forEach(c => {
    const grp = c.source;
    if (!bySrc[grp]) bySrc[grp] = [];
    bySrc[grp].push(c);
  });

  return Object.entries(bySrc).map(([src, items]) => {
    const opts = items.map(c => {
      const val = `${c.currency_code}__${c.base_currency}`;
      const lbl = `${c.currency_code} / ${c.base_currency}` +
                  (c.currency_name ? `  —  ${c.currency_name}` : '');
      return `<option value="${val}">${lbl}</option>`;
    }).join('');
    return `<optgroup label="${src.toUpperCase()}">${opts}</optgroup>`;
  }).join('');
}

async function loadChart(panelId) {
  const panel  = document.getElementById(panelId);
  const val    = panel.querySelector('.currency-select').value;
  const limit  = panel.querySelector('.limit-select').value;
  if (!val) return;

  const [code, base] = val.split('__');

  try {
    const res = await fetch(`${API_BASE}/api/rates/history/${code}?base=${base}&limit=${limit}`);
    if (!res.ok) throw new Error(res.statusText);
    const data = await res.json();
    renderChart(panelId, code, base, data);
  } catch (e) {
    console.error('[loadChart]', e);
  }
}

function renderChart(panelId, code, base, data) {
  if (charts[panelId]) {
    charts[panelId].destroy();
    delete charts[panelId];
  }

  const colorIdx = (parseInt(panelId.split('-')[1], 10) - 1) % CHART_COLORS.length;
  const color    = CHART_COLORS[colorIdx];
  const ctx      = document.getElementById(`canvas-${panelId}`).getContext('2d');

  charts[panelId] = new Chart(ctx, {
    type: 'line',
    data: {
      labels: data.map(d => fmtTime(d.fetched_at)),
      datasets: [{
        label:            `${code} / ${base}`,
        data:             data.map(d => d.rate),
        borderColor:      color,
        backgroundColor:  color + '22',
        borderWidth:      2,
        pointRadius:      data.length > 60 ? 0 : 3,
        pointHoverRadius: 5,
        fill:             true,
        tension:          0.3,
      }],
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      interaction: { mode: 'index', intersect: false },
      plugins: {
        legend: { labels: { color: '#e2e8f0', font: { size: 13 } } },
        tooltip: {
          backgroundColor: '#1e253a',
          titleColor: '#e2e8f0',
          bodyColor:  '#94a3b8',
          callbacks: {
            label: ctx => ` ${fmtRate(ctx.parsed.y)} ${base}`,
          },
        },
      },
      scales: {
        x: {
          ticks: { color: '#64748b', maxTicksLimit: 8, maxRotation: 0 },
          grid:  { color: '#1e293b' },
        },
        y: {
          ticks: { color: '#64748b', callback: v => fmtRate(v) },
          grid:  { color: '#1e293b' },
        },
      },
    },
  });
}

function removePanel(panelId) {
  if (charts[panelId]) {
    charts[panelId].destroy();
    delete charts[panelId];
  }
  document.getElementById(panelId)?.remove();
}

// ── Helpers ────────────────────────────────────────────────────────────────────

function fmtRate(rate) {
  if (rate == null) return '—';
  if (rate >= 10_000)  return rate.toLocaleString('en-US', { maximumFractionDigits: 2 });
  if (rate >= 1)       return rate.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 4 });
  return rate.toPrecision(6);
}

function fmtTime(ts) {
  if (!ts) return '—';
  return new Date(ts).toLocaleString('en-GB', {
    day: '2-digit', month: '2-digit', year: '2-digit',
    hour: '2-digit', minute: '2-digit',
  });
}

function setStatus(ok) {
  document.getElementById('status-dot').className  = `dot ${ok ? 'dot-ok' : 'dot-err'}`;
  document.getElementById('status-text').textContent = ok ? 'connected' : 'disconnected';
}
