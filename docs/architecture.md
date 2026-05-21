# Architecture

## Status

The `dev` branch now has three layers of architectural truth that matter together:

1. The default deployed/runtime path is still `external`: RabbitMQ carries async events and Redis stores short-lived session JSON.
2. Team workflow and release plumbing from the roadmap are already present on `dev`: PR checks run for `dev`, and pushes to `dev` publish `dev-latest`.
3. Queue-side PostgreSQL runtime assets already exist under `runtime/`, but proxy wiring, consumer switching, deploy wiring, and RabbitMQ/Redis removal are not finished yet.

This document separates the current deployed path from the runtime-consolidation target so the docs do not drift again.

## Current Deployed Architecture (`external` runtime path)

```text
Browser
  |
  v
node-03
  ui container
  - serves the React SPA
  - reverse-proxies /api and /history-api
  |
  +-- /api -----------> node-02 proxy container :8080
  |                       - Polymarket live markets
  |                       - whale leaderboard and positions
  |                       - BTC/ETH + USD/UAH
  |                       - session state in Redis
  |                       - publish market/price events to RabbitMQ
  |
  +-- /history-api ---> node-01 history-api container :8000
                          - read-only FastAPI over PostgreSQL

node-01
  postgres container
  rabbitmq container
  history-consumer container
    - consumes `market_events`
    - writes `market_snapshots` and `price_snapshots`

node-02
  redis container
```

## VM and Service Layout

| VM | IP | Current containers |
| --- | --- | --- |
| node-01 | `172.31.1.10` | `postgres`, `rabbitmq`, `history-consumer`, `history-api` |
| node-02 | `172.31.1.11` | `redis`, `proxy` |
| node-03 | `172.31.1.12` | `ui` |

### Why the browser stays same-origin

The React app uses `/api` and `/history-api`, not hard-coded private IPs. Node-03's nginx gateway forwards those paths to node-02 and node-01.

That matters for:

- avoiding browser CORS complexity
- keeping frontend runtime config environment-agnostic
- preserving the UI contract while backend internals change

## Current Responsibilities By Service

### UI (`ui-react/`, node-03)

Current behavior:

- React + Vite frontend served by nginx
- runtime URLs default to `/api` and `/history-api`
- live markets and whales refresh every 30 seconds
- price ticker/history refresh every 10 seconds
- session state is saved through proxy `/state`

The frontend should remain agnostic to whether runtime internals are RabbitMQ/Redis or PostgreSQL.

### Proxy (`proxy/main.go`, node-02)

Current behavior:

- fetches top 20 active markets from Gamma
- normalizes market payloads into `MarketSnapshot`
- publishes RabbitMQ messages for market snapshots
- fetches whale leaderboard and positions into Go memory
- fetches BTC/ETH from CoinGecko and USD/UAH from NBU
- publishes price events to RabbitMQ
- reads and writes session JSON in Redis with a 24-hour TTL

Important implementation details:

- RabbitMQ publish calls are mutex-guarded because the shared AMQP channel is not thread-safe
- market cache refresh runs every 60 seconds
- whale cache refresh runs every 5 minutes
- price refresh runs every 10 seconds, while NBU is refreshed at most hourly
- Redis is not used for upstream data caching; those caches live in Go memory

### History Consumer (`history/consumer.py`, node-01)

Current deployed consumer behavior:

- consumes RabbitMQ queue `market_events`
- writes market messages into `market_snapshots`
- writes price messages into `price_snapshots`
- keeps a RabbitMQ dead-letter queue `market_events_dead_letter`
- acknowledges messages after the PostgreSQL commit
- reconnects to PostgreSQL and RabbitMQ in a retry loop

Current reliability model:

- at-least-once delivery
- idempotent writes through `ON CONFLICT DO NOTHING`
- queue durability in RabbitMQ

### History API (`history/main.py`, node-01)

Current responsibility: read-only historical API over PostgreSQL.

Endpoints:

- `GET /health`
- `GET /history`
- `GET /history/{slug}`
- `GET /prices/history/{coin}`

### PostgreSQL History Tables (`history/schema.sql`)

Current persisted history tables:

- `market_snapshots`
- `whales`
- `whale_positions`
- `price_snapshots`

These remain the system-of-record tables for historical data.

### RabbitMQ and Redis

Current responsibilities are narrower than some older notes implied:

- RabbitMQ is only the async queue between proxy and consumer
- Redis is only used by proxy `/state` for short-lived session JSON
- the proxy's live caches for markets, whales, and prices are still in-process memory

## Already Merged On `dev`

### CI and branch plumbing

These roadmap items are already present:

- `.github/workflows/pr-checks.yml` validates PRs into `dev`
- `.github/workflows/docker-images.yml` publishes `dev-latest`
- `dev` is the intended integration branch for feature PRs

### Queue-side PostgreSQL runtime assets

The repo already contains queue-side PostgreSQL runtime work under `runtime/`:

- `00_run_all.sql` bootstrap script
- `01_schema.sql` runtime schema + `pgmq` queue setup
- `02_wrappers.sql` queue API wrappers such as `runtime.enqueue_event` and `runtime.claim_events`
- `03_notify.sql` `LISTEN/NOTIFY` trigger wiring
- `04_advisory.sql` advisory-lock helpers
- `05_dlq.sql` dead-letter queue management
- `runtime_consumer.py` pgmq-backed consumer
- `tests/test_runtime.sql` queue acceptance checks

That means the queue design is no longer just an issue idea. It exists in-repo. What is still missing is wiring the deployed services and deployment stack to actually use it by default or behind a runtime flag.

## Current Deployment Shape

The deployed system is containerized:

- Terraform creates the VMs and networking
- Ansible provisions hosts and installs Docker/Compose
- GitHub Actions builds service images and pushes them to GHCR
- per-node Compose stacks are rendered from `deploy/compose/*.yaml`
- node-01, node-02, and node-03 each run their assigned containers

Current image publishing behavior on `dev`:

- push to `Shabat` publishes `shabat-latest`
- push to `dev` publishes `dev-latest`
- push of a SemVer tag publishes immutable `vX.Y.Z` tags

## Runtime Consolidation Target

The approved target is still a PostgreSQL-centered runtime, but it is only partially landed.

### Target `postgres` runtime shape

```text
Browser
  |
  v
node-03 ui gateway
  |
  +-- /api -----------> node-02 proxy
  |                       - same HTTP contract
  |                       - enqueue events through PostgreSQL runtime API
  |                       - read/write session state through PostgreSQL runtime API
  |
  +-- /history-api ---> node-01 history-api

node-01 postgres
  - history tables
  - runtime schema
  - queue wrappers over pgmq
  - DLQ and retry metadata
  - LISTEN/NOTIFY wake-ups
  - advisory-lock coordination

node-01 history-consumer
  - claim events from PostgreSQL runtime API
  - write history tables
  - ack/fail through PostgreSQL runtime API

RabbitMQ and Redis stay present until the PostgreSQL path is verified end to end.
```

### What is still pending

The major unfinished steps are:

- add `RUNTIME_BACKEND=external|postgres` selection in proxy and consumer startup/config
- switch proxy publishing from RabbitMQ to `runtime.enqueue_event(...)` in `postgres` mode
- switch the deployed history-consumer path from `history/consumer.py` to `runtime/runtime_consumer.py` in `postgres` mode
- add deployment/bootstrap wiring so `runtime/00_run_all.sql` is applied before consumers start
- decide and provision remaining PostgreSQL runtime pieces that are documented but not yet deployed, such as `pg_cron`
- migrate Redis-backed session/runtime state behind PostgreSQL runtime primitives
- remove RabbitMQ and Redis only after verification

## Constraints That Must Stay Stable

These constraints come directly from the current codebase and the roadmap:

- the UI keeps using `/api` and `/history-api`
- the browser must not care whether runtime internals are RabbitMQ/Redis or PostgreSQL
- PostgreSQL remains the history system of record
- node-03 remains the browser-facing gateway
- the project keeps the three-VM deployment story during the migration

## What Is Not True Yet

To avoid repeating the earlier drift, these statements are still false on current `dev`:

- the proxy does not call `runtime.enqueue_event(...)` yet
- the default deployed consumer is not `runtime/runtime_consumer.py`
- there is no service-level `RUNTIME_BACKEND` switch in proxy or consumer startup paths yet
- Ansible/Compose do not yet bootstrap the `runtime/` schema as part of the normal deploy flow
- Redis and RabbitMQ are not removed from the default deployment

## Related Reading

- [README.md](../README.md)
- [runtime-queue-architecture.md](runtime-queue-architecture.md)
