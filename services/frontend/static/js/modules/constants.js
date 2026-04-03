export const POPULAR_FIAT  = ['USD', 'EUR', 'GBP', 'PLN', 'CHF', 'CAD'];
export const POPULAR_CRYPTO = ['BTC', 'ETH', 'USDT', 'BNB', 'SOL', 'XRP'];
export const LS_KEY = 'coinops_ui_v2';
export const HASH_KEYS = ['histDefaultPair', 'histRange', 'histMetric', 'liveTypeFilter', 'theme'];

export const FIAT_NAMES = {
  USD: 'Долар США', EUR: 'Євро', GBP: 'Фунт стерлінгів', PLN: 'Злотий', CHF: 'Франк', CAD: 'Канадський долар',
  JPY: 'Єна', CZK: 'Крона', SEK: 'Крона', NOK: 'Крона', DKK: 'Крона', HUF: 'Форинт', RON: 'Лей',
  BGN: 'Лев', MDL: 'Лей', UAH: 'Гривня'
};
export const CRYPTO_NAMES = {
  BTC: 'Bitcoin', ETH: 'Ethereum', USDT: 'Tether', BNB: 'BNB', SOL: 'Solana', XRP: 'XRP'
};
export const FIAT_FLAG   = { USD: '🇺🇸', EUR: '🇪🇺', GBP: '🇬🇧', PLN: '🇵🇱', CHF: '🇨🇭', CAD: '🇨🇦', UAH: '🇺🇦' };
export const CRYPTO_ICON = { BTC: '₿', ETH: 'Ξ', USDT: '₮', BNB: '◆', SOL: '◎', XRP: '✕' };

export const HIST_PAGE_SIZES = [15, 30, 50];
export const HIST_DEFAULT_PAGE = 15;
export const AUTO_REFRESH_INTERVAL_MS = 60000;
export const MAX_FAVORITES = 8;
export const KPI_FALLBACK = ['USD:fiat', 'EUR:fiat', 'BTC:crypto'];
export const CHART_COLORS = ['#34d399', '#fbbf24', '#60a5fa', '#f87171', '#a78bfa'];
export const MAX_HIST_ASSETS = 5;
export const RATE_CHANGE_THRESHOLD_PCT = 1;
export const THEME_COLORS = { dark: '#080b14', light: '#e4f0ec' };
