import { useEffect, useState } from "react";
import {
  BrowserRouter,
  Routes,
  Route,
  Link,
  useLocation,
} from "react-router-dom";
import {
  LineChart,
  Line,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ResponsiveContainer,
  Legend,
} from "recharts";
import { Cloud, History, Thermometer, Wind, RefreshCw } from "lucide-react";
import { BACKEND_URL, HISTORY_URL } from "./config";

// --- Components ---

const Navbar = () => {
  const location = useLocation();
  const isActive = (path: string) => location.pathname === path;

  return (
    <nav
      style={{
        display: "flex",
        justifyContent: "center",
        gap: "2rem",
        padding: "1.5rem",
        backgroundColor: "#ffffff",
        boxShadow: "0 2px 10px rgba(0,0,0,0.05)",
        marginBottom: "2rem",
        position: "sticky",
        top: 0,
        zIndex: 10,
      }}
    >
      <Link
        to="/"
        style={{
          display: "flex",
          alignItems: "center",
          gap: "0.5rem",
          textDecoration: "none",
          color: isActive("/") ? "#3b82f6" : "#64748b",
          fontWeight: "600",
          transition: "color 0.2s",
        }}
      >
        <Cloud size={20} /> Current Weather
      </Link>
      <Link
        to="/history"
        style={{
          display: "flex",
          alignItems: "center",
          gap: "0.5rem",
          textDecoration: "none",
          color: isActive("/history") ? "#3b82f6" : "#64748b",
          fontWeight: "600",
          transition: "color 0.2s",
        }}
      >
        <History size={20} /> History
      </Link>
    </nav>
  );
};

const CurrentWeather = () => {
  const [weather, setWeather] = useState<any>(null);
  const [loading, setLoading] = useState(false);

  const fetchWeather = () => {
    setLoading(true);
    fetch(`${BACKEND_URL}/weather?lat=50.4375&lon=30.5`)
      .then((res) => res.json())
      .then((data) => setWeather(data))
      .catch((err) => console.error(err))
      .finally(() => setLoading(false));
  };

  useEffect(() => {
    fetchWeather();
  }, []);

  return (
    <div style={{ maxWidth: "800px", margin: "0 auto", padding: "1rem" }}>
      <div
        style={{
          background: "linear-gradient(135deg, #3b82f6 0%, #2563eb 100%)",
          padding: "3rem",
          borderRadius: "24px",
          color: "white",
          boxShadow: "0 20px 25px -5px rgba(0, 0, 0, 0.1)",
          position: "relative",
          overflow: "hidden",
        }}
      >
        <div style={{ position: "relative", zIndex: 1 }}>
          <div
            style={{
              display: "flex",
              justifyContent: "space-between",
              alignItems: "start",
            }}
          >
            <div>
              <h2 style={{ fontSize: "1.5rem", opacity: 0.9, fontWeight: 500 }}>
                Kyiv, Ukraine
              </h2>
              <p style={{ fontSize: "1rem", opacity: 0.7 }}>
                {weather
                  ? new Date(weather.current_weather.time).toLocaleString()
                  : "..."}
              </p>
            </div>
            <button
              onClick={fetchWeather}
              disabled={loading}
              style={{
                background: "rgba(255,255,255,0.2)",
                border: "none",
                borderRadius: "12px",
                padding: "10px",
                cursor: "pointer",
                color: "white",
                display: "flex",
                alignItems: "center",
                transition: "background 0.2s",
              }}
            >
              <RefreshCw size={20} className={loading ? "spin" : ""} />
            </button>
          </div>

          {weather ? (
            <div
              style={{
                marginTop: "2rem",
                display: "flex",
                flexDirection: "column",
                alignItems: "center",
              }}
            >
              <div
                style={{
                  fontSize: "5rem",
                  fontWeight: "bold",
                  margin: "1rem 0",
                }}
              >
                {weather.current_weather.temperature}°C
              </div>
              <div
                style={{
                  display: "grid",
                  gridTemplateColumns: "1fr 1fr",
                  gap: "2rem",
                  width: "100%",
                  marginTop: "2rem",
                }}
              >
                <div
                  style={{
                    background: "rgba(255,255,255,0.1)",
                    padding: "1.5rem",
                    borderRadius: "20px",
                    display: "flex",
                    alignItems: "center",
                    gap: "1rem",
                  }}
                >
                  <Wind size={24} />
                  <div>
                    <p style={{ opacity: 0.7, fontSize: "0.9rem" }}>
                      Wind Speed (Max)
                    </p>
                    <p style={{ fontWeight: "bold", fontSize: "1.2rem" }}>
                      {weather.current_weather.windspeed} (
                      {weather.daily?.windspeed_10m_max?.[0] || "..."}) km/h
                    </p>
                  </div>
                </div>
                <div
                  style={{
                    background: "rgba(255,255,255,0.1)",
                    padding: "1.5rem",
                    borderRadius: "20px",
                    display: "flex",
                    alignItems: "center",
                    gap: "1rem",
                  }}
                >
                  <Thermometer size={24} />
                  <div>
                    <p style={{ opacity: 0.7, fontSize: "0.9rem" }}>
                      Temp (Min / Max)
                    </p>
                    <p style={{ fontWeight: "bold", fontSize: "1.2rem" }}>
                      {weather.daily?.temperature_2m_min?.[0]}°C /{" "}
                      {weather.daily?.temperature_2m_max?.[0]}°C
                    </p>
                  </div>
                </div>
              </div>
            </div>
          ) : (
            <div style={{ textAlign: "center", padding: "4rem" }}>
              Loading...
            </div>
          )}
        </div>
      </div>
    </div>
  );
};

const WeatherHistory = () => {
  const [history, setHistory] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    setLoading(true);
    fetch(`${HISTORY_URL}/history`)
      .then((res) => {
        if (!res.ok) throw new Error(`Server responded with ${res.status}`);
        return res.json();
      })
      .then((data) => {
        if (!Array.isArray(data)) throw new Error("Data is not an array");

        const formatted = [...data].reverse().map((item: any) => ({
          ...item,
          timeFormatted: new Date(item.time).toLocaleDateString([], {
            day: "2-digit",
            month: "2-digit",
          }),
        }));
        setHistory(formatted);
        setError(null);
      })
      .catch((err) => {
        console.error(err);
        setError(err.message);
      })
      .finally(() => setLoading(false));
  }, []);

  if (loading)
    return (
      <div style={{ textAlign: "center", padding: "3rem" }}>
        Loading history...
      </div>
    );

  if (error)
    return (
      <div
        style={{
          maxWidth: "800px",
          margin: "2rem auto",
          padding: "2rem",
          backgroundColor: "#fef2f2",
          color: "#b91c1c",
          borderRadius: "12px",
          border: "1px solid #fee2e2",
        }}
      >
        <h3 style={{ marginTop: 0 }}>Connection Error</h3>
        <p>
          Failed to fetch history from <strong>{HISTORY_URL}</strong>
        </p>
        <p style={{ fontSize: "0.9rem", opacity: 0.8 }}>Error: {error}</p>
        <p style={{ fontSize: "0.9rem" }}>
          Check if the Python service is running and accessible at this IP.
        </p>
      </div>
    );

  return (
    <div style={{ maxWidth: "1000px", margin: "0 auto", padding: "1rem" }}>
      <div
        style={{
          backgroundColor: "white",
          padding: "2rem",
          borderRadius: "24px",
          boxShadow: "0 10px 15px -3px rgba(0, 0, 0, 0.1)",
        }}
      >
        <h2
          style={{
            color: "#1e293b",
            marginBottom: "2rem",
            display: "flex",
            alignItems: "center",
            gap: "0.75rem",
          }}
        >
          <Thermometer color="#3b82f6" /> Temperature History (Daily Min/Max)
        </h2>

        {history.length > 0 ? (
          <>
            <div style={{ width: "100%", height: 400 }}>
              <ResponsiveContainer>
                <LineChart data={history}>
                  <CartesianGrid
                    strokeDasharray="3 3"
                    vertical={false}
                    stroke="#f1f5f9"
                  />
                  <XAxis
                    dataKey="timeFormatted"
                    stroke="#94a3b8"
                    fontSize={12}
                    tickLine={false}
                    axisLine={false}
                  />
                  <YAxis
                    stroke="#94a3b8"
                    fontSize={12}
                    tickLine={false}
                    axisLine={false}
                    unit="°C"
                  />
                  <Tooltip
                    contentStyle={{
                      borderRadius: "12px",
                      border: "none",
                      boxShadow: "0 10px 15px -3px rgba(0, 0, 0, 0.1)",
                    }}
                  />
                  <Legend />
                  <Line
                    name="Max Temp"
                    type="monotone"
                    dataKey="temp_max"
                    stroke="#ef4444"
                    strokeWidth={3}
                    dot={{ r: 4, fill: "#ef4444" }}
                    activeDot={{ r: 6 }}
                  />
                  <Line
                    name="Min Temp"
                    type="monotone"
                    dataKey="temp_min"
                    stroke="#3b82f6"
                    strokeWidth={3}
                    dot={{ r: 4, fill: "#3b82f6" }}
                    activeDot={{ r: 6 }}
                  />
                </LineChart>
              </ResponsiveContainer>
            </div>

            <div style={{ marginTop: "3rem" }}>
              <h3 style={{ color: "#1e293b", marginBottom: "1rem" }}>
                Detailed Log
              </h3>
              <div style={{ overflowX: "auto" }}>
                <table
                  style={{
                    width: "100%",
                    borderCollapse: "collapse",
                    textAlign: "left",
                  }}
                >
                  <thead>
                    <tr style={{ borderBottom: "1px solid #f1f5f9" }}>
                      <th style={{ padding: "1rem", color: "#64748b" }}>
                        Date
                      </th>
                      <th style={{ padding: "1rem", color: "#64748b" }}>
                        Temp (Min/Max)
                      </th>
                      <th style={{ padding: "1rem", color: "#64748b" }}>
                        Wind (Current/Max)
                      </th>
                    </tr>
                  </thead>
                  <tbody>
                    {history
                      .slice()
                      .reverse()
                      .map((item, idx) => (
                        <tr
                          key={idx}
                          style={{ borderBottom: "1px solid #f8fafc" }}
                        >
                          <td style={{ padding: "1rem", color: "#1e293b" }}>
                            {new Date(item.time).toLocaleDateString()}
                          </td>
                          <td
                            style={{
                              padding: "1rem",
                              color: "#3b82f6",
                              fontWeight: "bold",
                            }}
                          >
                            {item.temp_min}°C / {item.temp_max}°C
                          </td>
                          <td style={{ padding: "1rem", color: "#64748b" }}>
                            {item.temp}°C / {item.windspeed_max} km/h
                          </td>
                        </tr>
                      ))}
                  </tbody>
                </table>
              </div>
            </div>
          </>
        ) : (
          <div
            style={{ textAlign: "center", padding: "4rem", color: "#64748b" }}
          >
            <History size={48} style={{ opacity: 0.2, marginBottom: "1rem" }} />
            <p>No history data found in the database yet.</p>
            <p style={{ fontSize: "0.9rem" }}>
              Try refreshing the current weather to trigger a save.
            </p>
          </div>
        )}
      </div>
    </div>
  );
};

// --- App ---

function App() {
  return (
    <BrowserRouter>
      <div
        style={{
          backgroundColor: "#f8fafc",
          minHeight: "100vh",
          fontFamily: "'Inter', sans-serif",
        }}
      >
        <style>{`
          @keyframes spin { from { transform: rotate(0deg); } to { transform: rotate(360deg); } }
          .spin { animation: spin 1s linear infinite; }
          body { margin: 0; }
        `}</style>
        <Navbar />
        <main style={{ padding: "0 1rem 2rem 1rem" }}>
          <Routes>
            <Route path="/" element={<CurrentWeather />} />
            <Route path="/history" element={<WeatherHistory />} />
          </Routes>
        </main>
      </div>
    </BrowserRouter>
  );
}

export default App;
