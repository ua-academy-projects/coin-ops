# Architecture

## Overview

Polymarket Intelligence Dashboard — three cooperating services across three VMs, connected by RabbitMQ. The UI never touches the database directly; all writes go through the message queue.

```
Browser
  │
  ├─ GET /current ──► Proxy Service (Go, node-02)
  │  GET /whales  ─►      │ fetches Gamma API (20 markets)
  │  GET /prices  ─►      │ fetches CoinGecko + NBU (60s cache)
  │  GET/POST /state ─►   │ reads/writes Redis (session state)
  │                       │ normalizes → publishes msgs to RabbitMQ
  │                       └─ returns JSON to browser
  │
  └─ GET /history ──► History API (Python/FastAPI, node-01)
     GET /prices/history ─► └─ reads market_snapshots + price_snapshots from PostgreSQL

RabbitMQ (node-01, queue: market_events)
  └─► History Consumer (Python/pika, node-01)
          └─ routes by message type:
             no type / "market" → inserts into market_snapshots
             "price"            → inserts into price_snapshots

Redis (node-02, localhost:6379)
  └─► Session state (key: "session:<uuid>", TTL: 24h)
```

## Services

### Proxy Service — Go (node-02:8080)

**Responsibility:** stateless HTTP bridge between the UI and the external Polymarket APIs. Never touches the database.

Endpoints:
- `GET /current` — fetches top 20 markets from Gamma API, normalizes prices, publishes one JSON message per market to the `market_events` RabbitMQ queue, returns the snapshot array.
- `GET /whales` — returns cached whale positions. Cache is updated by a background goroutine every 5 minutes.
- `GET /prices` — fetches BTC, ETH prices from CoinGecko and USD/UAH rate from NBU. Cached in RAM and refreshed every 60s by a background goroutine. On each refresh, publishes 3 price events to `market_events` queue for persistence.
- `GET /state?sid=<uuid>` — returns session state JSON from Redis (or `{}` if key not found). Redis unavailable → 503.
- `POST /state?sid=<uuid>` — stores session state JSON in Redis with 24h TTL. Requires valid alphanumeric sid (8-128 chars). Requires valid JSON body.
- `GET /health` — liveness probe (`{"status":"ok"}`).

The AMQP channel is shared across goroutines; a `sync.Mutex` (`chMu`) guards every publish call because `amqp.Channel` is not thread-safe.

Background goroutine (whale cache):
1. Fetches top 20 traders from the Data API leaderboard.
2. For each trader, fetches their open positions (up to 50).
3. Slug is taken directly from the positions API response.
4. Stores result in an in-memory cache guarded by `sync.RWMutex`.
5. Runs once on startup, then every 5 minutes via `time.Ticker`.

Why cached: fetching whale positions requires 1 + 20 sequential HTTP calls. Doing this on every user request would be slow and risks rate-limiting. 5-minute staleness is acceptable for whale positions.

Background goroutine (prices):
1. Fetches BTC and ETH prices (USD) from CoinGecko, USD/UAH rate from NBU.
2. Caches result in RAM guarded by `sync.RWMutex`.
3. Publishes 3 price event messages to `market_events` queue.
4. Runs once on startup, then every 60s via `time.Ticker`.

Redis dependency: connected on startup via `REDIS_URL` env var (default `localhost:6379`). Non-fatal if unreachable — `/state` returns 503 but all other endpoints continue.

### History Consumer — Python/pika (node-01)

**Responsibility:** reliable message consumer. Inserts market and price snapshots into PostgreSQL.

- Consumes `market_events` queue (durable, persistent).
- Consumer now routes by the `type` field in the message:
  - Messages without type (or type="market"): insert into `market_snapshots` (existing behavior, backwards compatible).
  - Messages with type="price": insert into `price_snapshots`.
- `basic_qos(prefetch_count=1)` — consumer holds at most one unacknowledged message at a time. Without this, RabbitMQ pushes all queued messages at once; a crash mid-batch would lose everything.
- `basic_ack` is called **after** `db.commit()`. If the process crashes between commit and ack, RabbitMQ redelivers; `ON CONFLICT DO NOTHING` silently discards the duplicate.
- On exception: `db.rollback()` then `basic_nack(requeue=True)` — message goes back to the queue for retry.
- Same ack-after-commit, nack-with-requeue pattern applies to both market and price paths.
- Runs schema initialization on startup (`CREATE TABLE IF NOT EXISTS` + indexes).
- Outer `while True` reconnects RabbitMQ automatically at runtime if the connection drops — not only on startup.

### History API — Python/FastAPI (node-01:8000)

**Responsibility:** read-only API exposing stored snapshots to the UI.

Endpoints:
- `GET /history?limit=50` — latest snapshots across all markets.
- `GET /history/{slug}?limit=100` — time-series price history for a single market.
- `GET /prices/history/{coin}?limit=500` — time-series price history for a coin (`bitcoin`, `ethereum`, `usd_uah`). Returns up to 2000 rows. 404 if no data.
- `GET /health` — liveness probe.

Shares the same virtualenv as the consumer (`/opt/cognitor/history/venv/`). Does **not** run schema migrations — the consumer owns the schema.

### Web UI — Vanilla JS + Tailwind + nginx (node-03:80)

**Responsibility:** dark, data-dense single-page dashboard.

- Static HTML served by nginx. No build step, no node_modules.
- Tailwind CSS via CDN for styling.
- Two tabs: **Live Markets** (auto-refreshes every 30s via `setInterval`) and **History**.
- On each live refresh, `/current`, `/whales`, and `/prices` are fetched in parallel via `Promise.all`.
- Ticker strip in header shows BTC, ETH, and USD/UAH prices, updated on each refresh.
- Price history charts rendered when user clicks on price ticker items.
- Session state (active tab, scroll position) saved to/restored from Redis via `/state` endpoints on tab switches and page load.
- Vanilla JS `fetch()` calls the proxy and history APIs. XSS-safe rendering via DOM escaping.

## Data Flow

```
1. User opens dashboard (node-03:80)
2. Browser fetches /current, /whales, and /prices in parallel from proxy (node-02:8080)
3. Proxy calls Gamma API → normalizes 20 markets
4. Proxy calls CoinGecko + NBU → caches prices (background, every 60s)
5. Proxy publishes 20 market messages + 3 price messages to RabbitMQ (node-01:5672)
6. Proxy returns JSON to browser → UI renders markets, whale tracker, and price ticker
7. History consumer (node-01) receives messages → routes by type → inserts into correct table
8. User clicks History tab or price ticker → browser fetches /history/{slug} or /prices/history/{coin} from history-api (node-01:8000)
9. History API queries PostgreSQL → returns rows → UI renders chart
10. Session state saved to/restored from Redis (node-02:6379) on tab switches and page load
```

## Data Schema

See [`../history/schema.sql`](../history/schema.sql).

Key design decisions:
- `TIMESTAMPTZ` everywhere — VMs in different timezones would corrupt time-series data silently if naive timestamps were used.
- `UNIQUE (slug, fetched_at)` on `market_snapshots` and `UNIQUE (coin, fetched_at)` on `price_snapshots` — enables idempotent consumer writes.
- Indexes on `(slug/coin, fetched_at DESC)` — prevents full table scans on history queries.
- Redis (node-02, localhost:6379) — session state only. Key pattern: `session:<uuid>`, TTL 24h. Not used for data caching (proxy uses Go RAM cache for that).

## Message Contract (`market_events`)

Two message types share the same queue.

**Market snapshot** (20 messages per `/current` call):
```json
{
  "slug": "will-bitcoin-reach-100k-by-june-2026",
  "question": "Will Bitcoin reach $100k by June 2026?",
  "yes_price": 0.62,
  "no_price": 0.38,
  "volume_24h": 184000.00,
  "category": "Crypto",
  "end_date": "2026-06-30T23:59:00Z",
  "fetched_at": "2026-03-30T12:00:00Z"
}
```

**Price event** (3 messages per 60s refresh: bitcoin, ethereum, usd_uah):
```json
{
  "type": "price",
  "coin": "bitcoin",
  "price_usd": 97000.00,
  "change_24h": -1.2,
  "fetched_at": "2026-04-03T12:00:00Z"
}
```

Consumer routes by the `type` field. Market snapshots have no `type` field; they are backwards-compatible with pre-existing queue messages.

## External APIs

| API | Purpose | Auth |
|-----|---------|------|
| `gamma-api.polymarket.com` | Top 20 live markets | None |
| `data-api.polymarket.com` | Leaderboard + whale positions | None |
| `api.coingecko.com` | BTC, ETH prices + 24h change | None |
| `bank.gov.ua` | USD/UAH exchange rate (NBU) | None |

All are free public APIs with no authentication required.
