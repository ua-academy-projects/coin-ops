CREATE TABLE IF NOT EXISTS currency_rates (
    id            BIGSERIAL      PRIMARY KEY,
    currency_code VARCHAR(20)    NOT NULL,
    currency_name VARCHAR(100),
    source        VARCHAR(50)    NOT NULL,
    rate          NUMERIC(24, 8) NOT NULL,
    base_currency VARCHAR(10)    NOT NULL DEFAULT 'USD',
    fetched_at    TIMESTAMPTZ    NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_cr_code_base ON currency_rates (currency_code, base_currency);
CREATE INDEX IF NOT EXISTS idx_cr_fetched   ON currency_rates (fetched_at DESC);
