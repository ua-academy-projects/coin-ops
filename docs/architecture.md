# Architecture

## Overview

Polymarket Intelligence Dashboard — three cooperating services across three VMs, connected by RabbitMQ. The UI never touches the database directly; all writes go through the message queue.

```
Browser
  │
  ├─ GET /current ──► Proxy Service (Go, node-02)
  │                       │ fetches Gamma API (20 markets)
  │                       │ normalizes → publishes 20 msgs to RabbitMQ
  │                       └─ returns JSON to browser
  │
  ├─ GET /whales ───► Proxy Service (Go, node-02)
  │                       └─ returns cached whale data (refreshed every 5 min)
  │
  └─ GET /history ──► History API (Python/FastAPI, node-01)
                          └─ reads market_snapshots from PostgreSQL

RabbitMQ (node-01, queue: market_events)
  └─► History Consumer (Python/pika, node-01)
          └─ inserts rows into PostgreSQL
```

## Services

### Proxy Service — Go (node-02:8080)

**Responsibility:** stateless HTTP bridge between the UI and the external Polymarket APIs. Never touches the database.

Endpoints:
- `GET /current` — fetches top 20 markets from Gamma API, normalizes prices, publishes one JSON message per market to the `market_events` RabbitMQ queue, returns the snapshot array.
- `GET /whales` — returns cached whale positions. Cache is updated by a background goroutine every 5 minutes.
- `GET /health` — liveness probe (`{"status":"ok"}`).

Background goroutine (whale cache):
1. Fetches current top 20 markets → builds `map[title]slug` for slug resolution.
2. Fetches top 20 traders from the Data API leaderboard.
3. For each trader, fetches their open positions (up to 50).
4. Resolves market slugs using the title→slug map (graceful degradation if no match).
5. Stores result in an in-memory cache guarded by `sync.RWMutex`.
6. Runs once on startup, then every 5 minutes via `time.Ticker`.

Why cached: fetching whale positions requires 1 + 20 sequential HTTP calls. Doing this on every user request would be slow and risks rate-limiting. 5-minute staleness is acceptable for whale positions.

### History Consumer — Python/pika (node-01)

**Responsibility:** reliable message consumer. Inserts market snapshots into PostgreSQL.

- Consumes `market_events` queue (durable, persistent).
- `basic_ack` is called **after** the DB write, not before. If the process crashes between write and ack, RabbitMQ redelivers the message; the `ON CONFLICT (slug, fetched_at) DO NOTHING` constraint prevents duplicate rows.
- Runs schema migrations on startup (`CREATE TABLE IF NOT EXISTS` + indexes).
- Retries both PostgreSQL and RabbitMQ connections on startup.

### History API — Python/FastAPI (node-01:8000)

**Responsibility:** read-only API exposing stored snapshots to the UI.

Endpoints:
- `GET /history?limit=50` — latest snapshots across all markets.
- `GET /history/{slug}?limit=100` — time-series price history for a single market.
- `GET /health` — liveness probe.

Shares the same virtualenv as the consumer (`/opt/cognitor/history/venv/`). Does **not** run schema migrations — the consumer owns the schema.

### Web UI — HTMX + Tailwind + nginx (node-03:80)

**Responsibility:** dark, data-dense single-page dashboard.

- Static HTML served by nginx. No build step, no node_modules.
- Tailwind CSS via CDN for styling.
- Two tabs: **Live Markets** (auto-refreshes every 30s via `setInterval`) and **History**.
- Vanilla JS `fetch()` calls the proxy and history APIs. XSS-safe rendering via DOM escaping.

## Data Flow

```
1. User opens dashboard (node-03:80)
2. Browser fetches /current from proxy (node-02:8080)
3. Proxy calls Gamma API → normalizes 20 markets
4. Proxy publishes 20 messages to RabbitMQ (node-01:5672)
5. Proxy returns JSON to browser → UI renders market cards
6. History consumer (node-01) receives messages → inserts into PostgreSQL
7. User clicks History tab → browser fetches /history from history-api (node-01:8000)
8. History API queries PostgreSQL → returns rows → UI renders table
```

## Data Schema

See [`../history/schema.sql`](../history/schema.sql).

Key design decisions:
- `TIMESTAMPTZ` everywhere — VMs in different timezones would corrupt time-series data silently if naive timestamps were used.
- `UNIQUE (slug, fetched_at)` on `market_snapshots` — enables idempotent consumer writes.
- Indexes on `(slug, fetched_at DESC)` and `(address, fetched_at DESC)` — prevents full table scans on history queries.

## Message Contract (`market_events`)

One message per market per `/current` call. 20 messages published per call.

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

## External APIs

| API | Purpose | Auth |
|-----|---------|------|
| `gamma-api.polymarket.com` | Top 20 live markets | None |
| `data-api.polymarket.com` | Leaderboard + whale positions | None |

Both are free public APIs with no authentication required.
