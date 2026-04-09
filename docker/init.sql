CREATE TABLE IF NOT EXISTS rates (
    id SERIAL PRIMARY KEY,
    currency VARCHAR(10),
    name VARCHAR(100),
    rate NUMERIC(20, 8),
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_rates_currency ON rates(currency);
CREATE INDEX IF NOT EXISTS idx_rates_created_at ON rates(created_at);