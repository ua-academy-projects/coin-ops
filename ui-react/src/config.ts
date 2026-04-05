export const PROXY_URL = (import.meta.env.VITE_PROXY_URL as string) ?? 'http://172.31.1.11:8080';
export const HISTORY_URL = (import.meta.env.VITE_HISTORY_URL as string) ?? 'http://172.31.1.10:8000';
export const REFRESH_MS = 30_000;
export const PRICES_REFRESH_MS = 60_000;
