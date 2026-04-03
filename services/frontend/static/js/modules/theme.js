import { store, saveState } from './state.js';
import { THEME_COLORS } from './constants.js';

export function isLight() {
  return document.documentElement.getAttribute('data-theme') === 'light';
}

export function chartTheme() {
  if (isLight()) return {
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

function setThemeColorMeta(theme) {
  const meta = document.getElementById('meta-theme-color');
  if (meta) meta.setAttribute('content', THEME_COLORS[theme] || THEME_COLORS.dark);
}

export function initThemeToggle() {
  const toggle = document.getElementById('theme-toggle');
  const icon   = document.getElementById('theme-icon');
  if (!toggle) return;
  const saved = store.st.theme || 'dark';
  if (saved === 'light') {
    document.documentElement.setAttribute('data-theme', 'light');
    if (icon) icon.className = 'bi bi-sun-fill';
    setThemeColorMeta('light');
  }
  toggle.addEventListener('click', function () {
    const current = document.documentElement.getAttribute('data-theme');
    const next = current === 'light' ? 'dark' : 'light';
    document.documentElement.setAttribute('data-theme', next);
    if (icon) icon.className = next === 'light' ? 'bi bi-sun-fill' : 'bi bi-moon-stars';
    setThemeColorMeta(next);
    store.st.theme = next;
    saveState({ theme: next });
  });
}
