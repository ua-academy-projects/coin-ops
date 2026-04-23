# Architecture

## Status

The `dev` branch runs a PostgreSQL-centered runtime. RabbitMQ and Redis have been removed from deployment. All async event queuing uses PostgreSQL runtime primitives (`pgmq`), and session state is stored in PostgreSQL.

## Current Deployed Architecture

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
  |                       - session state in PostgreSQL
  |                       - enqueue events through PostgreSQL runtime API
  |
  +-- /history-api ---> node-01 history-api container :8000
                          - read-only FastAPI over PostgreSQL

node-01
  postgres container
  history-consumer container
    - claims events from PostgreSQL runtime API (pgmq)
    - writes market_snapshots and price_snapshots
```

## VM and Service Layout

| VM | IP | Current containers |
| --- | --- | --- |
| node-01 | `172.31.1.10` | `postgres`, `history-consumer`, `history-api` |
| node-02 | `172.31.1.11` | `proxy` |
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

The frontend is agnostic to runtime internals.

### Proxy (`proxy/main.go`, node-02)

Current behavior:

- fetches top 20 active markets from Gamma
- normalizes market payloads into `MarketSnapshot`
- enqueues market snapshot events through PostgreSQL runtime API
- fetches whale leaderboard and positions into Go memory
- fetches BTC/ETH from CoinGecko and USD/UAH from NBU
- enqueues price events through PostgreSQL runtime API
- reads and writes session JSON in PostgreSQL with a 24-hour TTL

Important implementation details:

- market cache refresh runs every 60 seconds
- whale cache refresh runs every 5 minutes
- price refresh runs every 10 seconds, while NBU is refreshed at most hourly
- upstream data caches live in Go memory

### History Consumer (`history/consumer.py`, node-01)

Current consumer behavior:

- claims events from PostgreSQL runtime queue (`pgmq`)
- writes market messages into `market_snapshots`
- writes price messages into `price_snapshots`
- acknowledges messages after the PostgreSQL commit
- reconnects to PostgreSQL in a retry loop

Current reliability model:

- at-least-once delivery
- idempotent writes through `ON CONFLICT DO NOTHING`
- queue durability in PostgreSQL

### History API (`history/main.py`, node-01)

Current responsibility: read-only historical API over PostgreSQL.

Endpoints:

- `GET /health`
- `GET /history`
- `GET /history/{slug}`
- `GET /prices/history/{coin}`

### PostgreSQL (`node-01`)

PostgreSQL serves as both the history store and the runtime backbone:

**History tables** (`history/schema.sql`):

- `market_snapshots`
- `whales`
- `whale_positions`
- `price_snapshots`

**Runtime schema** (`runtime/`):

- `pgmq`-backed event queue replacing RabbitMQ
- queue API wrappers: `runtime.enqueue_event`, `runtime.claim_events`
- `LISTEN/NOTIFY` trigger wiring for consumer wake-ups
- advisory-lock coordination
- dead-letter queue management
- session/cache state replacing Redis

## Current Deployment Shape

The deployed system is containerized:

- Terraform creates the VMs and networking
- Ansible provisions hosts and installs Docker/Compose
- GitHub Actions builds service images and pushes them to GHCR
- per-node Compose stacks are rendered from `deploy/compose/*.yaml`
- node-01, node-02, and node-03 each run their assigned containers

Current image publishing behavior:

- push to `Shabat` publishes `shabat-latest`
- push to `dev` publishes `dev-latest`
- push of a SemVer tag publishes immutable `vX.Y.Z` tags

## Constraints That Must Stay Stable

These constraints come directly from the current codebase:

- the UI keeps using `/api` and `/history-api`
- the browser does not care about runtime internals
- PostgreSQL is the single persistence and runtime layer
- node-03 remains the browser-facing gateway
- the project keeps the three-VM deployment story

## Related Reading

- [README.md](../README.md)
- [runtime-queue-architecture.md](runtime-queue-architecture.md)
