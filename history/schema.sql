-- Live market snapshots (one row per fetch per market)
CREATE TABLE IF NOT EXISTS market_snapshots (
    id          SERIAL PRIMARY KEY,
    fetched_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    question    TEXT NOT NULL,
    slug        TEXT NOT NULL,
    yes_price   NUMERIC(5,4) NOT NULL,
    no_price    NUMERIC(5,4),
    volume_24h  NUMERIC(16,2),
    category    TEXT,
    end_date    TIMESTAMPTZ,
    CONSTRAINT uq_slug_fetched_at UNIQUE (slug, fetched_at)
);

CREATE INDEX IF NOT EXISTS idx_market_snapshots_slug
    ON market_snapshots(slug, fetched_at DESC);

-- Whale profiles (top 20 leaderboard traders)
CREATE TABLE IF NOT EXISTS whales (
    address     TEXT PRIMARY KEY,
    pseudonym   TEXT,
    pnl         NUMERIC(16,2),
    volume      NUMERIC(16,2),
    rank        INT,
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Whale position snapshots
CREATE TABLE IF NOT EXISTS whale_positions (
    id            SERIAL PRIMARY KEY,
    fetched_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    address       TEXT NOT NULL,
    market        TEXT NOT NULL,
    slug          TEXT,
    outcome       TEXT,
    side          TEXT,
    current_value NUMERIC(16,2),
    size          NUMERIC(16,2),
    avg_price     NUMERIC(5,4)
);

CREATE INDEX IF NOT EXISTS idx_whale_positions_address
    ON whale_positions(address, fetched_at DESC);
