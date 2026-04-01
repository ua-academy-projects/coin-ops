import { useState } from "react";
import { fetchRates } from "./api";
import "./App.css";

const POPULAR_CURRENCIES = ["", "USD", "EUR", "GBP", "PLN", "CHF", "JPY", "CNY", "CAD"];

function App() {
  const [rates, setRates] = useState([]);
  const [filter, setFilter] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(null);

  async function handleFetch() {
    setLoading(true);
    setError(null);
    try {
      const data = await fetchRates(filter || undefined);
      setRates(data);
    } catch (err) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="app">
      <div className="header">
        <h1>UAH Exchange Rates</h1>
        <span className="badge">
          <span className="badge-dot" />
          National Bank of Ukraine
        </span>
      </div>

      <div className="controls">
        <div className="select-wrapper">
          <select value={filter} onChange={(e) => setFilter(e.target.value)}>
            <option value="">All currencies</option>
            {POPULAR_CURRENCIES.filter(Boolean).map((cc) => (
              <option key={cc} value={cc}>{cc}</option>
            ))}
          </select>
        </div>
        <button onClick={handleFetch} disabled={loading}>
          {loading ? <><span className="spinner" /> Loading…</> : "Fetch Rates"}
        </button>
      </div>

      {error && (
        <div className="error-box">
          <span>⚠</span> {error}
        </div>
      )}

      {rates.length === 0 && !loading && !error && (
        <div className="empty-state">
          <div className="empty-icon">₴</div>
          <p>Select a currency filter and click Fetch Rates</p>
        </div>
      )}

      {rates.length > 0 && (
        <div className="table-card">
          <div className="table-meta">
            <strong>{rates.length} {rates.length === 1 ? "currency" : "currencies"}</strong>
            <span>as of {rates[0]?.date}</span>
          </div>
          <table>
            <thead>
              <tr>
                <th>Code</th>
                <th>Currency</th>
                <th>Rate (UAH)</th>
                <th>Date</th>
              </tr>
            </thead>
            <tbody>
              {rates.map((r) => (
                <tr key={r.code}>
                  <td><span className="td-code">{r.code}</span></td>
                  <td>{r.name}</td>
                  <td><span className="td-rate">{r.rate}</span></td>
                  <td><span className="td-date">{r.date}</span></td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}

export default App;
