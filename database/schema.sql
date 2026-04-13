-- Monero Privacy Analytics Database Schema

CREATE TABLE IF NOT EXISTS blocks (
    height          INT PRIMARY KEY,
    hash            TEXT NOT NULL,
    timestamp       TIMESTAMP NOT NULL,
    tx_count        INT NOT NULL,
    block_size      INT NOT NULL,
    difficulty      BIGINT NOT NULL,
    created_at      TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS network_stats (
    id              SERIAL PRIMARY KEY,
    timestamp       TIMESTAMP NOT NULL DEFAULT NOW(),
    mempool_size    INT NOT NULL,
    avg_tx_per_block FLOAT NOT NULL,
    avg_fee         FLOAT NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS price (
    id              SERIAL PRIMARY KEY,
    timestamp       TIMESTAMP NOT NULL DEFAULT NOW(),
    usd             FLOAT NOT NULL,
    coin_id         TEXT NOT NULL DEFAULT 'monero'
);

CREATE TABLE IF NOT EXISTS privacy_metrics (
    id              SERIAL PRIMARY KEY,
    block_height    INT NOT NULL,
    tx_count        INT NOT NULL,
    privacy_score   FLOAT NOT NULL,
    risk_level      TEXT NOT NULL,
    created_at      TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS next_block_prediction (
    id                    SERIAL PRIMARY KEY,
    timestamp             TIMESTAMP NOT NULL DEFAULT NOW(),
    mempool_size          INT NOT NULL,
    expected_tx           INT NOT NULL,
    inclusion_probability FLOAT NOT NULL,
    privacy_score         FLOAT NOT NULL,
    recommendation        TEXT NOT NULL
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_blocks_timestamp ON blocks(timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_network_stats_timestamp ON network_stats(timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_price_timestamp ON price(timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_privacy_metrics_block_height ON privacy_metrics(block_height DESC);
CREATE INDEX IF NOT EXISTS idx_next_block_prediction_timestamp ON next_block_prediction(timestamp DESC);
