import { useEffect, useState } from "react";

interface CurrentWeather {
  time: string;
  temperature: number;
  windspeed: number;
  winddirection: number;
  is_day: number;
  weathercode: number;
}

interface WeatherResponse {
  latitude: number;
  longitude: number;
  timezone: string;
  current_weather: CurrentWeather;
}

function App() {
  const [weather, setWeather] = useState<WeatherResponse | null>(null);

  const fetchWeather = () => {
    fetch("http://localhost:8080/weather?lat=50.4375&lon=30.5")
      .then((res) => res.json())
      .then((data) => setWeather(data))
      .catch((err) => console.error(err));
  };

  useEffect(() => {
    fetchWeather();
  }, []);

  return (
    <div
      style={{
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
        padding: "2rem",
        fontFamily: "Arial, sans-serif",
        backgroundColor: "#f0f4f8",
        minHeight: "100vh",
      }}
    >
      <h1 style={{ color: "#333", marginBottom: "2rem" }}>Current Weather</h1>

      {weather ? (
        <div
          style={{
            backgroundColor: "#fff",
            padding: "1.5rem 2rem",
            borderRadius: "10px",
            boxShadow: "0 4px 10px rgba(0,0,0,0.1)",
            maxWidth: "600px",
            width: "100%",
            textAlign: "center",
          }}
        >
          <p style={{ fontSize: "1.2rem", color: "#555" }}>
            <strong>Location:</strong> {weather.latitude.toFixed(2)}°,{" "}
            {weather.longitude.toFixed(2)}° ({weather.timezone})
          </p>
          <p style={{ fontSize: "1.2rem", color: "#555", marginTop: "0.5rem" }}>
            <strong>Temperature:</strong> {weather.current_weather.temperature}
            °C
          </p>
          <p style={{ fontSize: "1.2rem", color: "#555", marginTop: "0.5rem" }}>
            <strong>Wind:</strong> {weather.current_weather.windspeed} km/h,{" "}
            {weather.current_weather.winddirection}°
          </p>
          <p style={{ fontSize: "1.2rem", color: "#555", marginTop: "0.5rem" }}>
            <strong>Weather code:</strong> {weather.current_weather.weathercode}
          </p>
          <p style={{ fontSize: "1.2rem", color: "#555", marginTop: "0.5rem" }}>
            <strong>Daytime:</strong>{" "}
            {weather.current_weather.is_day ? "Yes" : "No"}
          </p>
        </div>
      ) : (
        <p>Loading...</p>
      )}

      <button
        onClick={fetchWeather}
        style={{
          marginTop: "2rem",
          padding: "0.7rem 1.5rem",
          fontSize: "1rem",
          backgroundColor: "#4caf50",
          color: "#fff",
          border: "none",
          borderRadius: "5px",
          cursor: "pointer",
          transition: "background-color 0.2s",
        }}
        onMouseEnter={(e) =>
          ((e.target as HTMLButtonElement).style.backgroundColor = "#45a049")
        }
        onMouseLeave={(e) =>
          ((e.target as HTMLButtonElement).style.backgroundColor = "#4caf50")
        }
      >
        Refresh Weather
      </button>
    </div>
  );
}

export default App;
