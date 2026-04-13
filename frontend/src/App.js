import React, { useState, useCallback, useEffect } from "react";
import {
  LineChart, Line, AreaChart, Area,
  XAxis, YAxis, CartesianGrid, Tooltip,
  ResponsiveContainer, ReferenceLine,
} from "recharts";
import { api } from "./utils/api";
import { usePolling } from "./hooks/usePolling";

const COINS = [
  { id: "monero", label: "XMR" },
  { id: "bitcoin", label: "BTC" },
  { id: "ethereum", label: "ETH" },
  { id: "solana", label: "SOL" },
  { id: "cardano", label: "ADA" },
];

// ─── Colour tokens ────────────────────────────────────────────────────────────
const C = {
  bg: "#0a0c0f",
  surface: "#111418",
  border: "#1e2328",
  orange: "#f26822",
  orangeDim: "#f2682233",
  green: "#2ecc71",
  yellow: "#f1c40f",
  red: "#e74c3c",
  muted: "#4a5568",
  text: "#e2e8f0",
  dim: "#718096",
};

// ─── Risk colours ─────────────────────────────────────────────────────────────
function riskColor(level) {
  if (!level) return C.dim;
  if (level === "HIGH") return C.green;
  if (level === "MEDIUM") return C.yellow;
  return C.red;
}

// ─── Gauge component ──────────────────────────────────────────────────────────
function PrivacyGauge({ score, riskLevel }) {
  const pct = Math.round((score ?? 0) * 100);
  const angle = -135 + pct * 2.7;
  const color = riskColor(riskLevel);

  const describeArc = (cx, cy, r, startAngle, endAngle) => {
    const toRad = (d) => (d * Math.PI) / 180;
    const x1 = cx + r * Math.cos(toRad(startAngle));
    const y1 = cy + r * Math.sin(toRad(startAngle));
    const x2 = cx + r * Math.cos(toRad(endAngle));
    const y2 = cy + r * Math.sin(toRad(endAngle));
    const large = endAngle - startAngle > 180 ? 1 : 0;
    return `M ${x1} ${y1} A ${r} ${r} 0 ${large} 1 ${x2} ${y2}`;
  };

  return (
    <div style={{ display: "flex", flexDirection: "column", alignItems: "center" }}>
      <svg viewBox="0 0 200 130" width="220" height="143">
        {/* Track */}
        <path
          d={describeArc(100, 110, 70, -135, 135)}
          fill="none" stroke={C.border} strokeWidth="14" strokeLinecap="round"
        />
        {/* Fill */}
        <path
          d={describeArc(100, 110, 70, -135, -135 + pct * 2.7)}
          fill="none" stroke={color} strokeWidth="14" strokeLinecap="round"
          style={{ transition: "all 0.8s ease" }}
        />
        {/* Needle */}
        <line
          x1="100" y1="110"
          x2={100 + 55 * Math.cos(((angle) * Math.PI) / 180)}
          y2={110 + 55 * Math.sin(((angle) * Math.PI) / 180)}
          stroke={color} strokeWidth="2.5" strokeLinecap="round"
          style={{ transition: "all 0.8s ease" }}
        />
        <circle cx="100" cy="110" r="5" fill={color} />
        {/* Score text */}
        <text x="100" y="90" textAnchor="middle" fill={C.text} fontSize="28" fontWeight="700" fontFamily="'JetBrains Mono', monospace">
          {pct}
        </text>
        <text x="100" y="105" textAnchor="middle" fill={C.dim} fontSize="11" fontFamily="'JetBrains Mono', monospace">
          PRIVACY SCORE
        </text>
      </svg>
      <div style={{
        marginTop: "-8px", padding: "4px 18px", borderRadius: "20px",
        background: color + "22", border: `1px solid ${color}44`,
        color: color, fontSize: "12px", fontWeight: "700", letterSpacing: "2px",
        fontFamily: "'JetBrains Mono', monospace",
      }}>
        {riskLevel ?? "—"}
      </div>
    </div>
  );
}

// ─── Stat card ────────────────────────────────────────────────────────────────
function StatCard({ label, value, sub, accent }) {
  return (
    <div style={{
      background: C.surface, border: `1px solid ${C.border}`,
      borderRadius: "10px", padding: "18px 22px", flex: 1, minWidth: "160px",
      borderLeft: accent ? `3px solid ${accent}` : `1px solid ${C.border}`,
    }}>
      <div style={{ color: C.dim, fontSize: "11px", letterSpacing: "1.5px", marginBottom: "8px", fontFamily: "'JetBrains Mono', monospace" }}>
        {label}
      </div>
      <div style={{ color: C.text, fontSize: "22px", fontWeight: "700", fontFamily: "'JetBrains Mono', monospace" }}>
        {value ?? <span style={{ color: C.muted }}>—</span>}
      </div>
      {sub && <div style={{ color: C.dim, fontSize: "11px", marginTop: "4px" }}>{sub}</div>}
    </div>
  );
}

// ─── Section header ───────────────────────────────────────────────────────────
function SectionHeader({ children }) {
  return (
    <div style={{
      color: C.dim, fontSize: "11px", letterSpacing: "3px", textTransform: "uppercase",
      marginBottom: "14px", fontFamily: "'JetBrains Mono', monospace",
      display: "flex", alignItems: "center", gap: "10px",
    }}>
      <div style={{ height: "1px", width: "20px", background: C.orange }} />
      {children}
    </div>
  );
}

// ─── Recommendation banner ────────────────────────────────────────────────────
function RecommendationBanner({ prediction }) {
  if (!prediction) return null;
  const color = riskColor(
    prediction.privacy_score >= 0.7 ? "HIGH" :
    prediction.privacy_score >= 0.3 ? "MEDIUM" : "LOW"
  );
  return (
    <div style={{
      background: color + "11", border: `1px solid ${color}44`,
      borderRadius: "10px", padding: "16px 22px",
      display: "flex", alignItems: "center", gap: "16px",
    }}>
      <div style={{ fontSize: "28px" }}>
        {prediction.privacy_score >= 0.7 ? "✅" : prediction.privacy_score >= 0.3 ? "⚠️" : "🛑"}
      </div>
      <div>
        <div style={{ color: color, fontSize: "13px", fontWeight: "700", fontFamily: "'JetBrains Mono', monospace", letterSpacing: "1px" }}>
          {prediction.recommendation}
        </div>
        <div style={{ color: C.dim, fontSize: "12px", marginTop: "4px" }}>
          Next block: ~{prediction.expected_tx} txs expected · {Math.round(prediction.inclusion_probability * 100)}% inclusion probability
        </div>
      </div>
    </div>
  );
}

// ─── Block table ──────────────────────────────────────────────────────────────
function BlockTable({ blocks }) {
  if (!blocks?.length) return <div style={{ color: C.dim, fontSize: "13px" }}>Loading blocks…</div>;
  return (
    <div style={{ overflowX: "auto" }}>
      <table style={{ width: "100%", borderCollapse: "collapse", fontSize: "12px", fontFamily: "'JetBrains Mono', monospace" }}>
        <thead>
          <tr style={{ color: C.dim, letterSpacing: "1px" }}>
            {["HEIGHT", "TXS", "SIZE (KB)", "DIFFICULTY", "AGE"].map(h => (
              <th key={h} style={{ textAlign: "left", padding: "8px 12px", borderBottom: `1px solid ${C.border}`, fontSize: "10px" }}>{h}</th>
            ))}
          </tr>
        </thead>
        <tbody>
          {blocks.slice(0, 15).map((b) => {
            const ageMs = Date.now() - new Date(b.timestamp).getTime();
            const ageMins = Math.round(ageMs / 60000);
            const privScore = Math.min(1, b.tx_count / 20);
            const privColor = privScore >= 0.7 ? C.green : privScore >= 0.3 ? C.yellow : C.red;
            return (
              <tr key={b.height} style={{ borderBottom: `1px solid ${C.border}22` }}>
                <td style={{ padding: "9px 12px", color: C.orange }}>{b.height.toLocaleString()}</td>
                <td style={{ padding: "9px 12px" }}>
                  <span style={{ color: privColor, fontWeight: "600" }}>{b.tx_count}</span>
                </td>
                <td style={{ padding: "9px 12px", color: C.text }}>{(b.block_size / 1024).toFixed(1)}</td>
                <td style={{ padding: "9px 12px", color: C.dim }}>{(b.difficulty / 1e9).toFixed(1)}G</td>
                <td style={{ padding: "9px 12px", color: C.dim }}>
                  {ageMins < 60 ? `${ageMins}m` : `${Math.round(ageMins / 60)}h`} ago
                </td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}

// ─── Live pulse dot ───────────────────────────────────────────────────────────
function PulseDot({ active }) {
  return (
    <span style={{ position: "relative", display: "inline-block", width: "10px", height: "10px" }}>
      <span style={{
        display: "block", width: "10px", height: "10px", borderRadius: "50%",
        background: active ? C.green : C.muted,
        boxShadow: active ? `0 0 0 0 ${C.green}66` : "none",
        animation: active ? "pulse 2s infinite" : "none",
      }} />
    </span>
  );
}

// ─── Main App ─────────────────────────────────────────────────────────────────
export default function App() {
  const [activeCoin, setActiveCoinState] = useState("monero");

  useEffect(() => {
    api.getActiveCoin().then(res => {
      if (res.coin) setActiveCoinState(res.coin);
    }).catch(console.error);
  }, []);

  const handleCoinChange = async (coinId) => {
    if (coinId === activeCoin) return;
    setActiveCoinState(coinId);
    await api.setActiveCoin(coinId);
    window.location.reload();
  };

  const statsF = useCallback(() => api.getStats(), []);
  const blocksF = useCallback(() => api.getLatestBlocks(20), []);
  const predF = useCallback(() => api.getPrivacyPrediction(), []);
  const histF = useCallback(() => api.getPrivacyHistory(50), []);
  const priceHF = useCallback(() => api.getPriceHistory(80), []);

  const { data: stats, lastUpdated } = usePolling(statsF, 10000);
  const { data: blocks } = usePolling(blocksF, 10000);
  const { data: prediction } = usePolling(predF, 10000);
  const { data: privHistory } = usePolling(histF, 15000);
  const { data: priceHistory } = usePolling(priceHF, 60000);

  const isLive = lastUpdated && (Date.now() - lastUpdated.getTime()) < 15000;
  const isMonero = activeCoin === "monero";

  // Privacy chart data
  const chartData = privHistory
    ? [...privHistory].reverse().map((m, i) => ({
        i,
        score: Math.round(m.privacy_score * 100),
        height: m.block_height,
      }))
    : [];

  // Price chart data
  const priceData = priceHistory
    ? [...priceHistory].reverse().map((p, i) => {
        const d = new Date(p.timestamp + "Z");
        return {
          i,
          price: p.usd,
          time: d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })
        };
      })
    : [];

  const fmt = (n) => n != null ? n.toLocaleString() : "—";

  return (
    <>
      <style>{`
        @import url('https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;600;700&family=Syne:wght@400;700;800&display=swap');
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body { background: ${C.bg}; color: ${C.text}; font-family: 'Syne', sans-serif; }
        ::-webkit-scrollbar { width: 6px; }
        ::-webkit-scrollbar-track { background: ${C.surface}; }
        ::-webkit-scrollbar-thumb { background: ${C.border}; border-radius: 3px; }
        @keyframes pulse {
          0% { box-shadow: 0 0 0 0 ${C.green}66; }
          70% { box-shadow: 0 0 0 8px ${C.green}00; }
          100% { box-shadow: 0 0 0 0 ${C.green}00; }
        }
        @keyframes fadeIn {
          from { opacity: 0; transform: translateY(8px); }
          to { opacity: 1; transform: translateY(0); }
        }
        .card { animation: fadeIn 0.4s ease both; }
      `}</style>

      {/* Header */}
      <div style={{
        background: C.surface, borderBottom: `1px solid ${C.border}`,
        padding: "0 32px", height: "60px",
        display: "flex", alignItems: "center", justifyContent: "space-between",
        position: "sticky", top: 0, zIndex: 100,
      }}>
        <div style={{ display: "flex", alignItems: "center", gap: "12px" }}>
          <div style={{
            width: "32px", height: "32px", borderRadius: "8px",
            background: C.orange, display: "flex", alignItems: "center", justifyContent: "center",
            fontSize: "18px", fontWeight: "800",
          }}>ɱ</div>
          <div>
            <div style={{ fontFamily: "'Syne', sans-serif", fontWeight: "800", fontSize: "16px", letterSpacing: "-0.3px" }}>
              Monero Privacy Analytics
            </div>
            <div style={{ color: C.dim, fontSize: "10px", letterSpacing: "1.5px", fontFamily: "'JetBrains Mono', monospace" }}>
              NETWORK INTELLIGENCE DASHBOARD
            </div>
          </div>
        </div>
        
        {/* Coin Selector */}
        <div style={{ display: "flex", gap: "8px", background: C.bg, padding: "4px", borderRadius: "8px", border: `1px solid ${C.border}` }}>
          {COINS.map(c => (
            <button
              key={c.id}
              onClick={() => handleCoinChange(c.id)}
              style={{
                background: activeCoin === c.id ? C.surface : "transparent",
                color: activeCoin === c.id ? C.orange : C.dim,
                border: activeCoin === c.id ? `1px solid ${C.border}` : "1px solid transparent",
                padding: "4px 12px",
                borderRadius: "6px",
                cursor: "pointer",
                fontFamily: "'JetBrains Mono', monospace",
                fontSize: "11px",
                fontWeight: activeCoin === c.id ? "700" : "400",
                transition: "all 0.2s"
              }}
            >
              {c.label}
            </button>
          ))}
        </div>

        <div style={{ display: "flex", alignItems: "center", gap: "8px", fontSize: "11px", fontFamily: "'JetBrains Mono', monospace", color: C.dim }}>
          <PulseDot active={isLive} />
          <span style={{ color: isLive ? C.green : C.muted }}>{isLive ? "LIVE" : "OFFLINE"}</span>
          {lastUpdated && (
            <span style={{ marginLeft: "8px" }}>
              Updated {lastUpdated.toLocaleTimeString()}
            </span>
          )}
        </div>
      </div>

      {/* Main content */}
      <div style={{ maxWidth: "1400px", margin: "0 auto", padding: "28px 24px" }}>

        {/* Top row: Price + Stats */}
        <div style={{ display: "flex", gap: "14px", flexWrap: "wrap", marginBottom: "24px" }}>
          <StatCard
            label={`${COINS.find(c => c.id === activeCoin)?.label || "XMR"} / USD`}
            value={stats?.price_usd ? `$${stats.price_usd.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}` : "—"}
            accent={C.orange}
          />
          {isMonero && (
            <>
              <StatCard label="BLOCK HEIGHT" value={stats ? fmt(stats.block_height) : "—"} accent={C.orange} />
              <StatCard label="TXS IN BLOCK" value={stats?.tx_count ?? "—"} sub="latest block" />
              <StatCard label="MEMPOOL" value={stats?.mempool_size ?? "—"} sub="pending txs" />
              <StatCard
                label="DIFFICULTY"
                value={stats?.difficulty ? `${(stats.difficulty / 1e9).toFixed(2)}G` : "—"}
              />
              <StatCard
                label="AVG TX / BLOCK"
                value={stats?.avg_tx_per_block ? stats.avg_tx_per_block.toFixed(1) : "—"}
                sub="last 50 blocks"
              />
            </>
          )}
        </div>

        {/* Middle row: Gauge + Prediction */}
        {isMonero && (
          <div style={{ display: "grid", gridTemplateColumns: "340px 1fr", gap: "20px", marginBottom: "24px" }}>

            {/* Gauge card */}
            <div className="card" style={{
              background: C.surface, border: `1px solid ${C.border}`,
              borderRadius: "12px", padding: "24px 20px",
              display: "flex", flexDirection: "column", alignItems: "center",
            }}>
              <SectionHeader>Current Block Privacy</SectionHeader>
              <PrivacyGauge
                score={stats?.privacy_score}
                riskLevel={stats?.risk_level}
              />
              <div style={{ width: "100%", marginTop: "16px" }}>
                <div style={{ display: "flex", justifyContent: "space-between", fontSize: "11px", fontFamily: "'JetBrains Mono', monospace", color: C.dim, marginBottom: "6px" }}>
                  <span>Block #{fmt(stats?.block_height)}</span>
                  <span>{stats?.tx_count ?? "—"} txs</span>
                </div>
                <div style={{ height: "4px", background: C.border, borderRadius: "2px" }}>
                  <div style={{
                    height: "100%", borderRadius: "2px",
                    width: `${Math.round((stats?.privacy_score ?? 0) * 100)}%`,
                    background: riskColor(stats?.risk_level),
                    transition: "width 0.8s ease",
                  }} />
                </div>
              </div>
            </div>

            {/* Prediction + recommendation */}
            <div className="card" style={{
              background: C.surface, border: `1px solid ${C.border}`,
              borderRadius: "12px", padding: "24px 24px",
            }}>
              <SectionHeader>Next Block Prediction</SectionHeader>
              <RecommendationBanner prediction={prediction} />
              <div style={{ display: "flex", gap: "14px", marginTop: "20px", flexWrap: "wrap" }}>
                <StatCard label="MEMPOOL SIZE" value={fmt(prediction?.mempool_size)} />
                <StatCard label="EXPECTED TXS" value={fmt(prediction?.expected_tx)} />
                <StatCard
                  label="INCLUSION PROB"
                  value={prediction ? `${Math.round(prediction.inclusion_probability * 100)}%` : "—"}
                />
                <StatCard
                  label="PRED. PRIVACY"
                  value={prediction ? `${Math.round(prediction.privacy_score * 100)}` : "—"}
                  sub="/ 100"
                />
              </div>
            </div>
          </div>
        )}

        {/* Charts row */}
        <div style={{ display: "grid", gridTemplateColumns: isMonero ? "1fr 1fr" : "1fr", gap: "20px", marginBottom: "24px" }}>

          {/* Privacy history */}
          {isMonero && (
            <div className="card" style={{ background: C.surface, border: `1px solid ${C.border}`, borderRadius: "12px", padding: "22px" }}>
              <SectionHeader>Privacy Score History</SectionHeader>
              <ResponsiveContainer width="100%" height={260}>
              <AreaChart data={chartData}>
                <defs>
                  <linearGradient id="privGrad" x1="0" y1="0" x2="0" y2="1">
                    <stop offset="5%" stopColor={C.orange} stopOpacity={0.3} />
                    <stop offset="95%" stopColor={C.orange} stopOpacity={0} />
                  </linearGradient>
                </defs>
                <CartesianGrid stroke={C.border} strokeDasharray="3 3" />
                <XAxis dataKey="i" hide />
                <YAxis domain={[0, 100]} tick={{ fill: C.dim, fontSize: 11, fontFamily: "JetBrains Mono" }} />
                <Tooltip
                  contentStyle={{ background: C.surface, border: `1px solid ${C.border}`, borderRadius: "6px", fontFamily: "JetBrains Mono", fontSize: "12px" }}
                  formatter={(v) => [`${v}`, "Privacy Score"]}
                  labelFormatter={(i) => chartData[i] ? `Block #${chartData[i].height}` : ""}
                />
                <ReferenceLine y={70} stroke={C.green} strokeDasharray="4 4" strokeOpacity={0.5} />
                <ReferenceLine y={30} stroke={C.red} strokeDasharray="4 4" strokeOpacity={0.5} />
                <Area type="monotone" dataKey="score" stroke={C.orange} fill="url(#privGrad)" strokeWidth={2} dot={false} />
              </AreaChart>
            </ResponsiveContainer>
          </div>
          )}

          {/* Price chart */}
          <div className="card" style={{ background: C.surface, border: `1px solid ${C.border}`, borderRadius: "12px", padding: "22px" }}>
            <SectionHeader>{COINS.find(c => c.id === activeCoin)?.label || "XMR"} Price (USD)</SectionHeader>
            <ResponsiveContainer width="100%" height={260}>
              <LineChart data={priceData} margin={{ top: 10, left: 0, right: 0, bottom: 0 }}>
                <CartesianGrid stroke={C.border} strokeDasharray="3 3" />
                <XAxis dataKey="time" tick={{ fill: C.dim, fontSize: 10, fontFamily: "JetBrains Mono" }} tickMargin={10} minTickGap={20} />
                <YAxis domain={['auto', 'auto']} tick={{ fill: C.dim, fontSize: 11, fontFamily: "JetBrains Mono" }} width={60} />
                <Tooltip
                  contentStyle={{ background: C.surface, border: `1px solid ${C.border}`, borderRadius: "6px", fontFamily: "JetBrains Mono", fontSize: "12px" }}
                  formatter={(v) => [`$${v?.toFixed(2)}`, `${COINS.find(c => c.id === activeCoin)?.label || "Token"}/USD`]}
                  labelStyle={{ color: C.dim, marginBottom: "4px" }}
                />
                <Line type="monotone" dataKey="price" stroke={C.orange} strokeWidth={2} dot={false} isAnimationActive={!isMonero} />
              </LineChart>
            </ResponsiveContainer>
          </div>
        </div>

        {/* Block table */}
        {isMonero && (
          <div className="card" style={{ background: C.surface, border: `1px solid ${C.border}`, borderRadius: "12px", padding: "22px" }}>
            <SectionHeader>Recent Blocks</SectionHeader>
            <BlockTable blocks={blocks} />
          </div>
        )}

        {/* Footer */}
        <div style={{ textAlign: "center", marginTop: "28px", color: C.muted, fontSize: "11px", fontFamily: "'JetBrains Mono', monospace", letterSpacing: "1px" }}>
          MONERO PRIVACY ANALYTICS · DATA REFRESHES EVERY 10s · PRIVACY ESTIMATES ONLY — MONERO NEVER BREAKS
        </div>
      </div>
    </>
  );
}
