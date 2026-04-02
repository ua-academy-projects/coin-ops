-- CoinOps PostgreSQL bootstrap.
-- Run on the database VM (VM5) as superuser, e.g.: sudo -u postgres psql -v ... -f init.sql
-- Use a strong password in production (see database.env / secrets, not committed defaults).

CREATE USER :user_name WITH PASSWORD :user_password;
CREATE DATABASE coinops_db OWNER :user_name;
GRANT ALL PRIVILEGES ON DATABASE coinops_db TO :user_name;

-- The following meta-commands require psql (not plain libpq batch without psql).
\c coinops_db

-- Historical snapshots written by the worker from the proxy JSON.
-- snapshot_event_id matches envelope event_id (proxy publisher); UNIQUE enables idempotent replays.
CREATE TABLE IF NOT EXISTS exchange_rates (
  id                  BIGSERIAL PRIMARY KEY,
  asset_symbol        VARCHAR(16)  NOT NULL,
  asset_type          VARCHAR(8)   NOT NULL CHECK (asset_type IN ('fiat', 'crypto')),
  price_uah           NUMERIC(24, 8),
  price_usd           NUMERIC(24, 8),
  source              VARCHAR(32)  NOT NULL,
  snapshot_event_id   UUID         NOT NULL,
  created_at          TIMESTAMPTZ  NOT NULL DEFAULT now(),
  CONSTRAINT uq_exchange_rates_snapshot_line
    UNIQUE (snapshot_event_id, asset_symbol, asset_type, source)
);

CREATE INDEX IF NOT EXISTS idx_exchange_rates_created_at_desc
  ON exchange_rates (created_at DESC);

CREATE INDEX IF NOT EXISTS idx_exchange_rates_symbol_created
  ON exchange_rates (asset_symbol, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_exchange_rates_symbol_type_created_desc
  ON exchange_rates (asset_symbol, asset_type, created_at DESC);

GRANT USAGE ON SCHEMA public TO :user_name;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO :user_name;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO :user_name;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO :user_name;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO :user_name;
