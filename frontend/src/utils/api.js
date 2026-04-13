const API_BASE = process.env.REACT_APP_API_URL || "http://localhost:8000";

async function fetchJSON(path, options = {}) {
  const res = await fetch(`${API_BASE}${path}`, {
    credentials: "include",
    ...options,
  });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return res.json();
}

export const api = {
  getStats: () => fetchJSON("/stats"),
  getLatestBlocks: (limit = 20) => fetchJSON(`/blocks/latest?limit=${limit}`),
  getPrivacyCurrent: () => fetchJSON("/privacy/current"),
  getPrivacyHistory: (limit = 50) => fetchJSON(`/privacy/history?limit=${limit}`),
  getPrivacyPrediction: () => fetchJSON("/privacy/prediction"),
  getPrice: () => fetchJSON("/price"),
  getPriceHistory: (limit = 100) => fetchJSON(`/price/history?limit=${limit}`),
  getTrend: () => fetchJSON("/trend"),
  getActiveCoin: () => fetchJSON("/session/active_coin"),
  setActiveCoin: (coin) => fetchJSON("/session/active_coin", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ coin }),
  }),
};
