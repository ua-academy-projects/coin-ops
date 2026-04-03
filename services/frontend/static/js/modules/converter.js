import { store, saveState } from './state.js';
import { formatPrice } from './formatting.js';
import { findLiveRowBySymbol } from './live.js';
import { createDropdownMenuItem, syncDropdownLabel } from './dropdowns.js';

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
  store.liveRates.forEach(function (r) {
    const s = (r.asset_symbol || '').toUpperCase();
    if (s) set[s] = true;
  });
  set['UAH'] = true;
  return Object.keys(set).sort();
}

export function fillConverterSelects() {
  const { el, st } = store;
  if (!el.convFrom || !el.convTo || !el.convFromMenu || !el.convToMenu) return;
  const syms = buildConverterSymbols();
  el.convFrom.innerHTML    = '';
  el.convTo.innerHTML      = '';
  el.convFromMenu.innerHTML = '';
  el.convToMenu.innerHTML   = '';
  syms.forEach(function (s) {
    el.convFrom.appendChild(new Option(s, s));
    el.convTo.appendChild(new Option(s, s));
    el.convFromMenu.appendChild(createDropdownMenuItem(s, s));
    el.convToMenu.appendChild(createDropdownMenuItem(s, s));
  });
  const wantFrom = st.convFrom && syms.includes(st.convFrom) ? st.convFrom : null;
  const wantTo   = st.convTo   && syms.includes(st.convTo)   ? st.convTo   : null;
  if (wantFrom) el.convFrom.value = wantFrom;
  else if (syms.includes('USD')) el.convFrom.value = 'USD';
  if (wantTo) el.convTo.value = wantTo;
  else if (syms.includes('UAH')) el.convTo.value = 'UAH';
  else if (syms.length > 1) el.convTo.value = syms[1];
  syncDropdownLabel(el.convFrom, el.convFromLabel);
  syncDropdownLabel(el.convTo,   el.convToLabel);
}

export function updateConverter() {
  const { el } = store;
  if (!el.convResult) return;
  const amt  = parseFloat(el.convAmount && el.convAmount.value);
  const from = el.convFrom && el.convFrom.value;
  const to   = el.convTo   && el.convTo.value;
  if (Number.isNaN(amt) || !from || !to) { el.convResult.textContent = '—'; return; }
  if (from === to) { el.convResult.textContent = `${formatPrice(amt)} ${to}`; return; }
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
