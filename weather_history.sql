CREATE TABLE IF NOT EXISTS weather_history (
    id SERIAL PRIMARY KEY,
    temp NUMERIC,
    temp_max NUMERIC,
    temp_min NUMERIC,
    windspeed NUMERIC,
    windspeed_max NUMERIC,
    time TIMESTAMP UNIQUE
);