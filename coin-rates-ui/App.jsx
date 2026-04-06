import { useState, useEffect, useCallback } from "react";
import {
  LineChart, Line, XAxis, YAxis, CartesianGrid,
  Tooltip, ResponsiveContainer, Legend
} from "recharts";

const PROXY_URL = "http://192.168.0.103:5000/rates";
const HISTORY_URL = "http://192.168.0.106:8080/api/history";
const REFRESH_INTERVAL = 30;
const PAGE_SIZE = 10;

function parseHistory(records) {
  return records.map((r) => {
    let parsed = {};
    try {
      const fixed = r.data
        .replace(/'/g, '"')
        .replace(/None/g, "null")
        .replace(/True/g, "true")
        .replace(/False/g, "false");
      parsed = JSON.parse(fixed);
    } catch {}
    return { ...r, parsed };
  });
}

function ServiceStatus({ url, label }) {
  const [status, setStatus] = useState("checking");
  useEffect(() => {
    const check = async () => {
      try {
        const res = await fetch(url, { signal: AbortSignal.timeout(3000) });
        setStatus(res.ok ? "online" : "error");
      } catch {
        setStatus("offline");
      }
    };
    check();
    const interval = setInterval(check, 30000);
    return () => clearInterval(interval);
  }, [url]);

  const color = status === "online" ? "#00d4aa" : status === "checking" ? "#888" : "#ff4444";
  return (
    <div style={{ display: "flex", alignItems: "center", gap: 8, padding: "8px 16px", background: "#0f1117", borderRadius: 8, border: "1px solid #2a2d3e" }}>
      <div style={{ width: 8, height: 8, borderRadius: "50%", background: color, boxShadow: `0 0 6px ${color}` }} />
      <span style={{ fontSize: 13, color: "#ccc" }}>{label}</span>
      <span style={{ fontSize: 11, color, marginLeft: "auto", textTransform: "uppercase", fontWeight: 700 }}>{status}</span>
    </div>
  );
}

export default function App() {
  const [view, setView] = useState("dashboard");
  const [rates, setRates] = useState(null);
  const [history, setHistory] = useState([]);
  const [loading, setLoading] = useState(false);
  const [lastUpdate, setLastUpdate] = useState(null);
  const [countdown, setCountdown] = useState(REFRESH_INTERVAL);
  const [selectedCurrencies, setSelectedCurrencies] = useState(["USD", "EUR", "GBP"]);
  const [error, setError] = useState(null);
  const [page, setPage] = useState(1);

  const fetchRates = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const res = await fetch(PROXY_URL);
      const data = await res.json();
      setRates(data);
      setLastUpdate(new Date());
      setCountdown(REFRESH_INTERVAL);
    } catch {
      setError("Failed to fetch rates. Check proxy service.");
    } finally {
      setLoading(false);
    }
  }, []);

  const fetchHistory = useCallback(async () => {
    try {
      const res = await fetch(HISTORY_URL);
      const data = await res.json();
      setHistory(parseHistory(data));
    } catch {
      setError("Failed to fetch history.");
    }
  }, []);

  useEffect(() => {
    fetchRates();
    fetchHistory();
    const interval = setInterval(() => {
      fetchRates();
      fetchHistory();
    }, REFRESH_INTERVAL * 1000);
    return () => clearInterval(interval);
  }, [fetchRates, fetchHistory]);

  useEffect(() => {
    const timer = setInterval(() => {
      setCountdown((c) => (c > 0 ? c - 1 : REFRESH_INTERVAL));
    }, 1000);
    return () => clearInterval(timer);
  }, [lastUpdate]);

  const allCurrencies = rates?.currency
    ? [...new Set(rates.currency.map((c) => c.cc))].sort()
    : [];

  const toggleCurrency = (cc) => {
    setSelectedCurrencies((prev) =>
      prev.includes(cc) ? prev.filter((c) => c !== cc) : [...prev, cc]
    );
  };

  // Chart data - oldest to newest
  const chartDataRaw = history
    .slice()
    .reverse()
    .map((r) => ({
      time: new Date(r.created_at).toLocaleTimeString(),
      Bitcoin: r.parsed?.crypto?.bitcoin?.usd,
      Ethereum: r.parsed?.crypto?.ethereum?.usd,
    }))
    .filter((d) => d.Bitcoin || d.Ethereum);

  // Smart Y-axis domains with 1% padding
  const btcPrices = chartDataRaw.map(d => d.Bitcoin).filter(Boolean);
  const ethPrices = chartDataRaw.map(d => d.Ethereum).filter(Boolean);
  const btcMin = btcPrices.length ? Math.floor(Math.min(...btcPrices) * 0.999) : "auto";
  const btcMax = btcPrices.length ? Math.ceil(Math.max(...btcPrices) * 1.001) : "auto";
  const ethMin = ethPrices.length ? Math.floor(Math.min(...ethPrices) * 0.999) : "auto";
  const ethMax = ethPrices.length ? Math.ceil(Math.max(...ethPrices) * 1.001) : "auto";

  // Price change calculation (newest vs oldest in history)
  const newestRecord = history[0]?.parsed?.crypto;
  const oldestRecord = history[history.length - 1]?.parsed?.crypto;
  const btcChange = newestRecord && oldestRecord
    ? newestRecord.bitcoin?.usd - oldestRecord.bitcoin?.usd : null;
  const ethChange = newestRecord && oldestRecord
    ? newestRecord.ethereum?.usd - oldestRecord.ethereum?.usd : null;

  // Pagination
  const totalPages = Math.ceil(history.length / PAGE_SIZE);
  const paginatedHistory = history.slice((page - 1) * PAGE_SIZE, page * PAGE_SIZE);

  const cardStyle = { background: "#1a1d27", borderRadius: 12, padding: 24, border: "1px solid #2a2d3e" };
  const changeColor = (val) => val === null ? "#888" : val >= 0 ? "#00d4aa" : "#ff4444";
  const changeSign = (val) => val === null ? "" : val >= 0 ? "▲" : "▼";

  return (
    <div style={{ minHeight: "100vh", background: "#0f1117", color: "#e0e0e0" }}>

      {/* Header */}
      <div style={{ background: "#1a1d27", borderBottom: "1px solid #2a2d3e", padding: "16px 32px", display: "flex", alignItems: "center", justifyContent: "space-between" }}>
        <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
          <div style={{ width: 10, height: 10, borderRadius: "50%", background: "#00d4aa" }} />
          <span style={{ fontSize: 20, fontWeight: 700, color: "#fff" }}>Coin Rates Dashboard</span>
        </div>
        <div style={{ display: "flex", gap: 8 }}>
          {["dashboard", "history"].map((v) => (
            <button key={v} onClick={() => { setView(v); if (v === "history") fetchHistory(); }}
              style={{ padding: "8px 20px", borderRadius: 8, border: "none", cursor: "pointer", background: view === v ? "#00d4aa" : "#2a2d3e", color: view === v ? "#000" : "#e0e0e0", fontWeight: 600, textTransform: "capitalize" }}>
              {v === "dashboard" ? "Live Rates" : "History"}
            </button>
          ))}
        </div>
        <div style={{ display: "flex", alignItems: "center", gap: 16, fontSize: 13, color: "#888" }}>
          {lastUpdate && <span>Updated: {lastUpdate.toLocaleTimeString()}</span>}
          <div style={{ display: "flex", alignItems: "center", gap: 6 }}>
            <div style={{ width: 28, height: 28, borderRadius: "50%", border: "2px solid #00d4aa", display: "flex", alignItems: "center", justifyContent: "center", fontSize: 11, color: "#00d4aa", fontWeight: 700 }}>{countdown}</div>
            <span>sec</span>
          </div>
          <button onClick={fetchRates} disabled={loading}
            style={{ padding: "6px 14px", borderRadius: 6, border: "1px solid #3a3f5c", background: "transparent", color: "#00d4aa", cursor: "pointer", fontSize: 13 }}>
            {loading ? "..." : "↻ Refresh"}
          </button>
        </div>
      </div>

      {error && (
        <div style={{ background: "#2d1b1b", border: "1px solid #ff4444", color: "#ff6b6b", padding: "12px 32px", fontSize: 14 }}>{error}</div>
      )}

      <div style={{ padding: "24px 32px" }}>
        {view === "dashboard" && (
          <div>

            {/* Crypto Cards with price change */}
            <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(280px, 1fr))", gap: 16, marginBottom: 24 }}>
              {rates?.crypto && Object.entries(rates.crypto).map(([coin, vals]) => {
                const change = coin === "bitcoin" ? btcChange : ethChange;
                const pct = oldestRecord ? (change / (coin === "bitcoin" ? oldestRecord.bitcoin?.usd : oldestRecord.ethereum?.usd) * 100) : null;
                return (
                  <div key={coin} style={cardStyle}>
                    <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 12 }}>
                      <span style={{ fontSize: 13, color: "#888", textTransform: "uppercase", letterSpacing: 1 }}>{coin}</span>
                      <span style={{ background: "#00d4aa22", color: "#00d4aa", padding: "2px 8px", borderRadius: 4, fontSize: 12 }}>CRYPTO</span>
                    </div>
                    <div style={{ fontSize: 28, fontWeight: 700, color: "#fff", marginBottom: 4 }}>${vals.usd?.toLocaleString()}</div>
                    <div style={{ fontSize: 14, color: "#888", marginBottom: 8 }}>₴ {vals.uah?.toLocaleString()}</div>
                    {change !== null && (
                      <div style={{ fontSize: 13, color: changeColor(change), fontWeight: 600 }}>
                        {changeSign(change)} ${Math.abs(change).toFixed(2)} ({pct >= 0 ? "+" : ""}{pct?.toFixed(3)}%) since first record
                      </div>
                    )}
                  </div>
                );
              })}
            </div>

            {/* Bitcoin Chart */}
            {btcPrices.length > 0 && (
              <div style={{ ...cardStyle, marginBottom: 24 }}>
                <h3 style={{ marginBottom: 16, color: "#f7931a", fontSize: 16 }}>₿ Bitcoin Price History (USD)</h3>
                <ResponsiveContainer width="100%" height={220}>
                  <LineChart data={chartDataRaw}>
                    <CartesianGrid strokeDasharray="3 3" stroke="#2a2d3e" />
                    <XAxis dataKey="time" stroke="#888" tick={{ fontSize: 10 }} />
                    <YAxis stroke="#888" tick={{ fontSize: 10 }} domain={[btcMin, btcMax]} tickFormatter={(v) => `$${v.toLocaleString()}`} />
                    <Tooltip contentStyle={{ background: "#1a1d27", border: "1px solid #2a2d3e", borderRadius: 8 }} formatter={(v) => [`$${v?.toLocaleString()}`, "Bitcoin"]} />
                    <Line type="monotone" dataKey="Bitcoin" stroke="#f7931a" strokeWidth={2} dot={false} />
                  </LineChart>
                </ResponsiveContainer>
              </div>
            )}

            {/* Ethereum Chart */}
            {ethPrices.length > 0 && (
              <div style={{ ...cardStyle, marginBottom: 24 }}>
                <h3 style={{ marginBottom: 16, color: "#627eea", fontSize: 16 }}>Ξ Ethereum Price History (USD)</h3>
                <ResponsiveContainer width="100%" height={220}>
                  <LineChart data={chartDataRaw}>
                    <CartesianGrid strokeDasharray="3 3" stroke="#2a2d3e" />
                    <XAxis dataKey="time" stroke="#888" tick={{ fontSize: 10 }} />
                    <YAxis stroke="#888" tick={{ fontSize: 10 }} domain={[ethMin, ethMax]} tickFormatter={(v) => `$${v.toLocaleString()}`} />
                    <Tooltip contentStyle={{ background: "#1a1d27", border: "1px solid #2a2d3e", borderRadius: 8 }} formatter={(v) => [`$${v?.toLocaleString()}`, "Ethereum"]} />
                    <Line type="monotone" dataKey="Ethereum" stroke="#627eea" strokeWidth={2} dot={false} />
                  </LineChart>
                </ResponsiveContainer>
              </div>
            )}

            {/* Currency Selector */}
            <div style={{ ...cardStyle, marginBottom: 24 }}>
              <h3 style={{ marginBottom: 16, color: "#fff", fontSize: 16 }}>Select Currencies (NBU)</h3>
              <div style={{ display: "flex", flexWrap: "wrap", gap: 8, marginBottom: 16 }}>
                {allCurrencies.map((cc) => (
                  <button key={cc} onClick={() => toggleCurrency(cc)}
                    style={{ padding: "4px 12px", borderRadius: 6, border: "1px solid", borderColor: selectedCurrencies.includes(cc) ? "#00d4aa" : "#2a2d3e", background: selectedCurrencies.includes(cc) ? "#00d4aa22" : "transparent", color: selectedCurrencies.includes(cc) ? "#00d4aa" : "#888", cursor: "pointer", fontSize: 12, fontWeight: 600 }}>
                    {cc}
                  </button>
                ))}
              </div>
              <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(180px, 1fr))", gap: 12 }}>
                {rates?.currency?.filter((c) => selectedCurrencies.includes(c.cc)).map((c) => (
                  <div key={c.cc} style={{ background: "#0f1117", borderRadius: 8, padding: "12px 16px", border: "1px solid #2a2d3e" }}>
                    <div style={{ fontSize: 12, color: "#888", marginBottom: 4 }}>{c.txt}</div>
                    <div style={{ fontSize: 18, fontWeight: 700, color: "#fff" }}>{c.cc}</div>
                    <div style={{ fontSize: 14, color: "#00d4aa" }}>₴ {c.rate?.toFixed(2)}</div>
                  </div>
                ))}
              </div>
            </div>

            {/* Service Status Panel */}
            <div style={cardStyle}>
              <h3 style={{ marginBottom: 16, color: "#fff", fontSize: 16 }}>Service Status</h3>
              <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(220px, 1fr))", gap: 10 }}>
                <ServiceStatus url="http://192.168.0.103:5000/rates" label="Proxy Service (server2)" />
                <ServiceStatus url="http://192.168.0.106:8080/api/history" label="History API (server1)" />
              </div>
              <div style={{ marginTop: 10, fontSize: 12, color: "#555" }}>
                Checks every 30 seconds • RabbitMQ and PostgreSQL monitored indirectly via History API
              </div>
            </div>

          </div>
        )}

        {view === "history" && (
          <div style={cardStyle}>
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 20 }}>
              <h2 style={{ color: "#fff" }}>Rate History</h2>
              <span style={{ fontSize: 13, color: "#888" }}>{history.length} total records</span>
            </div>
            <div style={{ overflowX: "auto" }}>
              <table style={{ width: "100%", borderCollapse: "collapse", fontSize: 14 }}>
                <thead>
                  <tr style={{ borderBottom: "1px solid #2a2d3e" }}>
                    {["ID", "Date & Time", "Bitcoin (USD)", "Ethereum (USD)", "USD (UAH)", "EUR (UAH)", "GBP (UAH)"].map((h) => (
                      <th key={h} style={{ padding: "10px 16px", textAlign: "left", color: "#888", fontWeight: 600, fontSize: 12, textTransform: "uppercase", letterSpacing: 0.5 }}>{h}</th>
                    ))}
                  </tr>
                </thead>
                <tbody>
                  {paginatedHistory.map((r, i) => {
                    const usd = r.parsed?.currency?.find?.((c) => c.cc === "USD");
                    const eur = r.parsed?.currency?.find?.((c) => c.cc === "EUR");
                    const gbp = r.parsed?.currency?.find?.((c) => c.cc === "GBP");
                    return (
                      <tr key={r.id} style={{ borderBottom: "1px solid #1a1d27", background: i % 2 === 0 ? "#0f1117" : "transparent" }}>
                        <td style={{ padding: "12px 16px", color: "#888" }}>{r.id}</td>
                        <td style={{ padding: "12px 16px", color: "#ccc" }}>{new Date(r.created_at).toLocaleString()}</td>
                        <td style={{ padding: "12px 16px", color: "#f7931a", fontWeight: 600 }}>${r.parsed?.crypto?.bitcoin?.usd?.toLocaleString() ?? "—"}</td>
                        <td style={{ padding: "12px 16px", color: "#627eea", fontWeight: 600 }}>${r.parsed?.crypto?.ethereum?.usd?.toLocaleString() ?? "—"}</td>
                        <td style={{ padding: "12px 16px", color: "#00d4aa" }}>{usd ? `₴${usd.rate?.toFixed(2)}` : "—"}</td>
                        <td style={{ padding: "12px 16px", color: "#00d4aa" }}>{eur ? `₴${eur.rate?.toFixed(2)}` : "—"}</td>
                        <td style={{ padding: "12px 16px", color: "#00d4aa" }}>{gbp ? `₴${gbp.rate?.toFixed(2)}` : "—"}</td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>

            {/* Pagination */}
            <div style={{ display: "flex", justifyContent: "center", alignItems: "center", gap: 8, marginTop: 20 }}>
              <button onClick={() => setPage(1)} disabled={page === 1}
                style={{ padding: "6px 12px", borderRadius: 6, border: "1px solid #2a2d3e", background: "transparent", color: page === 1 ? "#444" : "#00d4aa", cursor: page === 1 ? "default" : "pointer" }}>«</button>
              <button onClick={() => setPage(p => Math.max(1, p - 1))} disabled={page === 1}
                style={{ padding: "6px 12px", borderRadius: 6, border: "1px solid #2a2d3e", background: "transparent", color: page === 1 ? "#444" : "#00d4aa", cursor: page === 1 ? "default" : "pointer" }}>‹</button>
              {Array.from({ length: totalPages }, (_, i) => i + 1)
                .filter(p => p === 1 || p === totalPages || Math.abs(p - page) <= 2)
                .map((p, idx, arr) => (
                  <span key={p}>
                    {idx > 0 && arr[idx - 1] !== p - 1 && <span style={{ color: "#444" }}>…</span>}
                    <button onClick={() => setPage(p)}
                      style={{ padding: "6px 12px", borderRadius: 6, border: "1px solid", borderColor: p === page ? "#00d4aa" : "#2a2d3e", background: p === page ? "#00d4aa22" : "transparent", color: p === page ? "#00d4aa" : "#888", cursor: "pointer", fontWeight: p === page ? 700 : 400 }}>
                      {p}
                    </button>
                  </span>
                ))}
              <button onClick={() => setPage(p => Math.min(totalPages, p + 1))} disabled={page === totalPages}
                style={{ padding: "6px 12px", borderRadius: 6, border: "1px solid #2a2d3e", background: "transparent", color: page === totalPages ? "#444" : "#00d4aa", cursor: page === totalPages ? "default" : "pointer" }}>›</button>
              <button onClick={() => setPage(totalPages)} disabled={page === totalPages}
                style={{ padding: "6px 12px", borderRadius: 6, border: "1px solid #2a2d3e", background: "transparent", color: page === totalPages ? "#444" : "#00d4aa", cursor: page === totalPages ? "default" : "pointer" }}>»</button>
            </div>
            <div style={{ textAlign: "center", fontSize: 12, color: "#555", marginTop: 8 }}>
              Page {page} of {totalPages} • Showing {PAGE_SIZE} records per page
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
