CREATE TABLE IF NOT EXISTS rate_history (
    id          BIGSERIAL PRIMARY KEY,
    code        VARCHAR(10)    NOT NULL,
    name        TEXT           NOT NULL,
    rate        NUMERIC(18,6)  NOT NULL,
    rate_date   VARCHAR(20)    NOT NULL,
    fetched_at  TIMESTAMPTZ    NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_rate_history_code       ON rate_history (code);
CREATE INDEX IF NOT EXISTS idx_rate_history_fetched_at ON rate_history (fetched_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS idx_rate_history_code_date ON rate_history (code, rate_date);
