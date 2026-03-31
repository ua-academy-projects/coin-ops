-- CoinOps PostgreSQL bootstrap.
-- Run on VM4 as superuser, e.g.: psql -U postgres -f init.sql
-- Change coinops_dev_change_me before production.

CREATE USER coinops WITH PASSWORD '13245768';
CREATE DATABASE coinops_db OWNER coinops;
GRANT ALL PRIVILEGES ON DATABASE coinops_db TO coinops;

-- The following meta-commands require psql (not plain libpq batch without psql).
\c coinops_db

-- Historical snapshots written by the worker from the proxy JSON.
CREATE TABLE exchange_rates (
  id           BIGSERIAL PRIMARY KEY,
  asset_symbol VARCHAR(16)  NOT NULL,
  asset_type   VARCHAR(8)   NOT NULL CHECK (asset_type IN ('fiat', 'crypto')),
  price_uah    NUMERIC(24, 8),
  price_usd    NUMERIC(24, 8),
  source       VARCHAR(32)  NOT NULL,
  created_at   TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE INDEX idx_exchange_rates_created_at_desc
  ON exchange_rates (created_at DESC);

GRANT USAGE ON SCHEMA public TO coinops;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO coinops;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO coinops;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO coinops;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO coinops;
