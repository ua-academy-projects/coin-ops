import {
  FIAT_NAMES, CRYPTO_NAMES, FIAT_FLAG, CRYPTO_ICON,
  POPULAR_FIAT, POPULAR_CRYPTO
} from './constants.js';

export function pad2(n) { return String(n).padStart(2, '0'); }

export function escapeHtml(value) {
  if (value == null) return '';
  return String(value)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

export function parseTimestamp(iso) {
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

export function formatLocalDateTime(iso) {
  if (!iso) return '—';
  const d = parseTimestamp(iso);
  if (d === null) return String(iso);
  return `${pad2(d.getHours())}:${pad2(d.getMinutes())}:${pad2(d.getSeconds())} ${pad2(d.getDate())}.${pad2(d.getMonth() + 1)}.${d.getFullYear()}`;
}

export function formatChartAxisLabel(iso, range) {
  if (!iso) return '—';
  const d = parseTimestamp(iso);
  if (d === null || isNaN(d.getTime())) return String(iso);
  if (range === '24h') {
    return `${pad2(d.getHours())}:${pad2(d.getMinutes())}`;
  }
  return `${pad2(d.getDate())}.${pad2(d.getMonth() + 1)}.${d.getFullYear()}`;
}

export function addThousandsSep(s) {
  const parts = s.split('.');
  parts[0] = parts[0].replace(/\B(?=(\d{3})+(?!\d))/g, '\u00a0');
  return parts.join('.');
}

export function formatPrice(v) {
  if (v === null || v === undefined) return '—';
  const n = Number(v);
  if (Number.isNaN(n)) return '—';
  const abs = Math.abs(n);
  if (abs > 0 && abs < 0.01) return addThousandsSep(n.toPrecision(4));
  if (abs > 0 && abs < 1)    return addThousandsSep(n.toFixed(4));
  return addThousandsSep(n.toFixed(2));
}

export function formatPct(v) {
  if (v === null || v === undefined || Number.isNaN(Number(v))) return '—';
  const n = Number(v);
  return `${n > 0 ? '+' : ''}${n.toFixed(2)}%`;
}

export function trendClass(v) {
  if (v === null || v === undefined || Number.isNaN(Number(v))) return 'trend-na';
  return Number(v) >= 0 ? 'trend-up' : 'trend-down';
}

export function formatRelativeTime(date) {
  if (!date) return '';
  const diff = Math.max(0, Date.now() - date.getTime());
  const sec = Math.floor(diff / 1000);
  if (sec < 60) return sec + '\u00a0с тому';
  const min = Math.floor(sec / 60);
  if (min < 60) return min + '\u00a0хв тому';
  return Math.floor(min / 60) + '\u00a0год тому';
}

export function pairKey(r) {
  return `${(r.asset_symbol || '').toUpperCase()}:${r.asset_type || ''}`;
}

export function displayName(r) {
  const sym = (r.asset_symbol || '').toUpperCase();
  if (r.asset_type === 'fiat') return FIAT_NAMES[sym] || (r.name || sym);
  return CRYPTO_NAMES[sym] || sym;
}

export function displayIcon(r) {
  const sym = (r.asset_symbol || '').toUpperCase();
  if (r.asset_type === 'fiat') return FIAT_FLAG[sym] || '💱';
  return CRYPTO_ICON[sym] || '◆';
}

export function isPopularRow(r) {
  const sym = (r.asset_symbol || '').toUpperCase();
  if (r.asset_type === 'fiat')   return POPULAR_FIAT.includes(sym);
  if (r.asset_type === 'crypto') return POPULAR_CRYPTO.includes(sym);
  return false;
}

export function parsePairKeyString(pk) {
  if (pk == null || typeof pk !== 'string') return null;
  const idx = pk.lastIndexOf(':');
  if (idx <= 0) return null;
  return { sym: pk.slice(0, idx).toUpperCase(), typ: pk.slice(idx + 1) };
}

export function destroyChartInstance(chart) {
  if (!chart) return;
  try { chart.destroy(); } catch (e) { /* ignore */ }
}
