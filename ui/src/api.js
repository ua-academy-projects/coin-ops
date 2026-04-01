const API_PROXY_URL = import.meta.env.VITE_API_PROXY_URL || "http://localhost:8000";

export async function fetchRates(cc) {
  const url = new URL("/rates", API_PROXY_URL);
  if (cc) url.searchParams.set("cc", cc);
  const res = await fetch(url);
  if (!res.ok) throw new Error(`Failed to fetch rates: ${res.status}`);
  return res.json();
}
