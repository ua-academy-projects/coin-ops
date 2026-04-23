# Architecture

## Status

The project has transitioned to a **PostgreSQL-native runtime architecture**, consolidating queue, cache, and session state management into PostgreSQL. The `dev` branch reflects this state.

The legacy `external` mode (using RabbitMQ and Redis) remains available as a fallback via the `RUNTIME_BACKEND=external` environment variable, but the primary deployed path and documentation now focus on the PostgreSQL-native (`postgres`) mode.

For the architectural decisions behind this consolidation, see [ADR 0001: PostgreSQL-Native Runtime Layer](adr/0001-postgres-runtime.md).

## High-Level Overview (PostgreSQL Runtime)

The system is distributed across three nodes:

```text
Browser
  |
  v
node-03
  ui container (nginx + React SPA)
  |
  +-- /api -----------> node-02 proxy container :8080
  |                       - fetches Polymarket markets
  |                       - fetches whale leaderboard/positions
  |                       - fetches BTC/ETH and USD/UAH
  |                       - reads/writes session JSON via PostgreSQL `runtime.session_*`
  |                       - enqueues events via `runtime.enqueue_event(...)`
  |
  +-- /history-api ---> node-01 history-api container :8000
                          - read-only FastAPI over PostgreSQL

node-01
  postgres container
    - System of record: `market_snapshots`, `price_snapshots`, etc.
    - Queue runtime: `pgmq` queues, DLQ, `LISTEN/NOTIFY`
    - Cache runtime: `runtime.cache` (UNLOGGED) + `pg_cron`
    - Session runtime: `runtime.session` (UNLOGGED) + `pg_cron`
  
  history-consumer container
    - claims `market_events` and `price_events` via `runtime.claim_events(...)`
    - writes history tables
    - acknowledges or dead-letters events via PostgreSQL runtime API
```

## VM and Service Layout

| VM | IP | Runtime Services |
| --- | --- | --- |
| node-01 | `172.31.1.10` | PostgreSQL, `history-consumer`, `history-api` |
| node-02 | `172.31.1.11` | `proxy` (Redis is disabled/removed in `postgres` mode) |
| node-03 | `172.31.1.12` | `ui` |

### Why the Browser Stays Same-Origin

The React app uses `/api` and `/history-api`, not hard-coded private IPs. Node-03's nginx gateway forwards those paths to node-02 and node-01.

This matters for:
- avoiding browser CORS complexity
- keeping frontend runtime config environment-agnostic
- preserving the UI contract while backend internals change

## Data Flow

| Path | Flow | Purpose |
| --- | --- | --- |
| Live path | Browser -> `/api` -> Go proxy -> external APIs -> Browser | fast live market data |
| Write path | Go proxy -> PostgreSQL (`pgmq`) -> Python consumer -> PostgreSQL | async persistence |
| History path | Browser -> `/history-api` -> FastAPI -> PostgreSQL -> Browser | chart time series |
| Session path | Browser -> `/api/state` -> PostgreSQL (`UNLOGGED`) | short-lived UI state |

## PostgreSQL Runtime Layer

PostgreSQL now serves as the unified backend for multiple runtime concerns, exposed through PL/pgSQL wrappers in the `runtime` schema. This eliminates the need for external network calls to Redis or RabbitMQ.

### 1. Queue (replaces RabbitMQ)
- Backed by the `pgmq` extension.
- **Enqueuing:** Proxy calls `runtime.enqueue_event()`.
- **Consumption:** Consumer uses `runtime.claim_events()`.
- **Wake-ups:** Handled natively by PostgreSQL `LISTEN/NOTIFY`.
- **Failure Handling:** Dead-letter queues (DLQ) are built into `pgmq` and managed via `runtime/05_dlq.sql`.

### 2. Cache (replaces Redis in-memory caches)
- Backed by an `UNLOGGED` PostgreSQL table (`runtime.cache`), avoiding write-ahead log (WAL) overhead.
- Proxy uses `runtime.cache_set()`, `runtime.cache_get()`, and `runtime.cache_delete()`.
- Expiration is enforced upon read, and physical row deletion is handled asynchronously by `pg_cron`.

### 3. Session (replaces Redis session state)
- Backed by an `UNLOGGED` PostgreSQL table (`runtime.session`).
- Proxy uses `runtime.session_set()` and `runtime.session_get()`.
- Sessions are natively given a 24-hour TTL, reaped automatically by `pg_cron`.

## Current Responsibilities By Service

### UI (`ui-react/`, node-03)
- React + Vite frontend served by nginx.
- Runtime URLs default to `/api` and `/history-api`.
- Completely agnostic to backend infrastructure shifts.

### Proxy (`proxy/main.go`, node-02)
- Fetches top 20 active markets from Gamma, whales from Data API, and prices from external APIs.
- Pushes events to the async PostgreSQL queue.
- Handles ephemeral session data via PostgreSQL.

### History Consumer (`runtime/runtime_consumer.py`, node-01)
- Long-running Python process consuming from `pgmq`.
- Provides at-least-once delivery with idempotent writes.

### History API (`history/main.py`, node-01)
- Read-only historical FastAPI service exposing stored PostgreSQL tables to the frontend.

## Legacy Mode (`RUNTIME_BACKEND=external`)

If a deployment explicitly requires separation of concerns for scaling, the proxy and consumer can revert to using Redis and RabbitMQ by setting `RUNTIME_BACKEND=external` in their respective `.env` files. However, the default architectural path prioritizes the simplicity and transactional consistency of the unified PostgreSQL runtime.

## Related Reading

- [Migration and Demo Runbook](migration-runbook.md)
- [Deployment Guide](deployment.md)
- [Runtime Schema Documentation](runtime.md)
