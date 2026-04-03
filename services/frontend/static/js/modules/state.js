import { LS_KEY, HASH_KEYS, MAX_FAVORITES } from './constants.js';

/* ---- Shared mutable store (singleton, imported by every module) ---- */
export const store = {
  liveRates:          [],
  dashboardInsights:  {},
  liveMeta:           {},
  lastFetchedDate:    null,
  st:                 {},
  el:                 {},
  uiStateServerSync:  false,
  syncTimer:          null,
};

/* ---- localStorage ---- */
export function loadState() {
  try {
    const raw = localStorage.getItem(LS_KEY);
    return raw ? JSON.parse(raw) : {};
  } catch (e) { return {}; }
}

export function saveState(patch) {
  const cur = loadState();
  Object.assign(cur, patch);
  try { localStorage.setItem(LS_KEY, JSON.stringify(cur)); } catch (e) { /* ignore */ }
  pushHash(cur);
  if (store.uiStateServerSync) {
    clearTimeout(store.syncTimer);
    store.syncTimer = setTimeout(function () {
      fetch('/api/v1/ui-state', {
        method: 'PUT',
        credentials: 'same-origin',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ state: loadState() })
      }).catch(function () { /* ignore */ });
    }, 500);
  }
}

/* ---- URL hash ↔ state ---- */
function stateToHash(state) {
  const parts = [];
  HASH_KEYS.forEach(function (k) {
    if (state[k] != null && state[k] !== '') {
      parts.push(encodeURIComponent(k) + '=' + encodeURIComponent(state[k]));
    }
  });
  return parts.length ? '#' + parts.join('&') : '';
}

export function hashToState() {
  const h = location.hash.replace(/^#/, '');
  if (!h) return {};
  const obj = {};
  h.split('&').forEach(function (seg) {
    const idx = seg.indexOf('=');
    if (idx < 0) return;
    const k = decodeURIComponent(seg.slice(0, idx));
    const v = decodeURIComponent(seg.slice(idx + 1));
    if (HASH_KEYS.indexOf(k) >= 0) obj[k] = v;
  });
  return obj;
}

function pushHash(state) {
  const h = stateToHash(state);
  if (h !== location.hash && h !== '#') {
    history.replaceState(null, '', h || location.pathname);
  }
}

/* ---- UI-state normalisation ---- */
export function normalizeUiState(s) {
  if (!Array.isArray(s.favoritePairs)) s.favoritePairs = [];
  s.favoritePairs = s.favoritePairs.filter(function (x) {
    return typeof x === 'string' && x.indexOf(':') > 0;
  });
  if (s.favoritePairs.length > MAX_FAVORITES) s.favoritePairs = s.favoritePairs.slice(0, MAX_FAVORITES);
  if (s.histDefaultPair != null && typeof s.histDefaultPair !== 'string') s.histDefaultPair = null;
  if (s.convFrom != null && typeof s.convFrom !== 'string') delete s.convFrom;
  if (s.convTo   != null && typeof s.convTo   !== 'string') delete s.convTo;
  if (s.convAmount != null && typeof s.convAmount !== 'string') s.convAmount = String(s.convAmount);
  if (!s.uiStateVersion) s.uiStateVersion = 2;
}

/* ---- Fetch server-side state + merge ---- */
export async function initStateFromServer() {
  const base = loadState();
  try {
    const r = await fetch('/api/v1/ui-state', { credentials: 'same-origin' });
    const data = await r.json();
    if (data && data.enabled === true) {
      store.uiStateServerSync = true;
    }
    if (data && data.enabled && data.state && typeof data.state === 'object') {
      Object.assign(base, data.state);
      try { localStorage.setItem(LS_KEY, JSON.stringify(base)); } catch (e) { /* ignore */ }
    }
  } catch (e) { /* ignore — degrade to localStorage only */ }
  const fromHash = hashToState();
  Object.assign(base, fromHash);
  normalizeUiState(base);
  store.st = base;
}
