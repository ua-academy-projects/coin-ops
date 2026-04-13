# Component Deep Dive — Cross-Branch Analysis

> **Reviewer**: Independent Senior Software Architect / DevOps Lead (Claude Opus 4.6)
> **Date**: 2026-04-13
> **Repository**: `ua-academy-projects/coin-ops`

This document analyzes each architectural component across all 10 branches, identifying the best-in-class implementation for each and explaining why it is the most enterprise-ready.

---

## 1. Frontend

### Approaches Across Branches

| Branch | Technology | Serving | Runtime Config Injection |
|:---|:---|:---|:---|
| **Shabat** | React 19 + TypeScript + Vite + Tailwind + Recharts | nginx:alpine with gzip, security headers, SPA `try_files` | `window.__COIN_OPS_CONFIG__` via `docker-entrypoint.d/40-runtime-config.sh` overwriting `config.js` at container start |
| **hrenchevskyi** | Flask SSR + vanilla JS modules (api.js with `fetchWithRetry`) | Flask dev server (no nginx), CSP headers, rate limiting (Flask-Limiter) | Server-side env (`PROXY_URL`, `HISTORY_BASE_URL`), BFF pattern proxies API calls |
| **kazachuk** | Flask SSR + Jinja2 templates | Flask dev server | Server-side env with hardcoded VM IP defaults |
| **kurdupel** | Flask SSR + Jinja2 + Flask-Session | Flask `app.run(debug=True)` | Hardcoded `192.168.56.x` defaults in code |
| **monero-privacy-system** | React 18 + CRA + Recharts + Lucide | nginx with gzip, yearly cache, SPA routing | `REACT_APP_API_URL` (build-time CRA env); no runtime injection |
| **penina** | React + Vite + Recharts (in `coin-rates-ui/`) | Served via Flask `ui_service` (not nginx for React build) | Hardcoded `http://192.168.0.103:5000` constants in JSX |
| **shturyn** | React 19 + TypeScript + Vite + Recharts + Lucide | nginx (inline config in Dockerfile) | `window.location.hostname` + hardcoded ports (8080/8000) |
| **smoliakov** | Django 5 + Gunicorn + server-side templates | nginx reverse proxy to Gunicorn, static via `alias` | Django `settings.py` reads from `/etc/rates-dashboard.env` |
| **volynets** | None | None | None |
| **zakipnyi** | Static HTML + CSS + Chart.js (CDN) | nginx with `try_files`, `proxy_pass /api/` | `API_BASE = ''` (same-origin via nginx proxy) |

### Best Implementation: **Shabat**

**Shabat** has the most enterprise-ready frontend for these reasons:

1. **Build-once, deploy-anywhere**: The `docker-entrypoint.d/40-runtime-config.sh` pattern writes `window.__COIN_OPS_CONFIG__` at container startup from environment variables. This means the same Docker image can be deployed to dev/staging/prod without rebuilding — a critical requirement for CI/CD pipelines and Kubernetes deployments.

2. **Modern stack**: React 19 + TypeScript + Vite provides type safety, fast builds, and tree-shaking. Tailwind CSS for utility-first styling. Recharts for data visualization.

3. **Production nginx**: Proper gzip compression, security headers, `try_files` for SPA routing, and a dedicated `/health` endpoint for load balancer probes.

4. **Separation of concerns**: The UI is a fully independent service with its own Dockerfile, nginx config, and deployment unit — ready for independent scaling in Kubernetes.

**Honorable mention**: **hrenchevskyi** takes a different but valid approach with its BFF (Backend-for-Frontend) pattern. The Flask frontend acts as a server-side proxy, eliminating CORS issues and keeping API URLs server-side. Its `fetchWithRetry` in JavaScript and Flask-Limiter rate limiting are security-conscious touches. However, the BFF pattern adds latency and the Flask dev server is not production-grade.

---

## 2. Proxy

### Approaches Across Branches

| Branch | Language | Role | Key Features |
|:---|:---|:---|:---|
| **Shabat** | Go | Aggregator + publisher | Polymarket/CoinGecko/NBU fetch with 10s timeout, in-memory cache, CORS middleware, Redis for session state, health endpoint |
| **hrenchevskyi** | Go | Aggregator + publisher | `errgroup` parallel fetch, in-memory cache with TTL, `http_retry.go` with exponential backoff + `Retry-After`, security headers middleware, CORS, graceful shutdown |
| **kazachuk** | Go | Simple fetch + publish | Separate `/rates` and `/crypto` endpoints, 60s in-memory cache for crypto, no retry, no timeouts on transport |
| **kurdupel** | Python Flask | Fetch + publish | Critical routing bug (`@app.route("/price/ ")`), background thread, price smoothing algorithm, new RabbitMQ connection per message |
| **monero-privacy-system** | None (FastAPI serves all) | No separate proxy | CORS middleware, no edge routing |
| **penina** | Python Flask | Fetch + cache + publish | Redis cache (25s TTL), new RabbitMQ connection per publish, `str(dict)` serialization (not JSON) |
| **shturyn** | Go | BFF fetch + publish | Attempts to read from history first, falls back to external API, CORS `*` |
| **smoliakov** | Go | Collector (background) | Timed loop (configurable interval), health endpoint with JSON status, systemd service |
| **volynets** | None | None | None |
| **zakipnyi** | Go | Timed collector | Fanout exchange, 30 retry attempts for RabbitMQ dial, configurable fetch interval |

### Best Implementation: **hrenchevskyi**

**hrenchevskyi** has the most enterprise-ready proxy implementation:

1. **Resilient HTTP client** (`http_retry.go`): The custom retry logic inspects HTTP response codes (429, 5xx) and extracts `Retry-After` headers to dynamically adjust wait times. This is the only branch that handles upstream rate limiting gracefully — critical when depending on free-tier APIs like CoinGecko.

2. **Modular architecture**: The proxy is decomposed into focused files — `config.go` (centralized config struct with fail-fast validation), `middleware.go` (security headers, CORS, panic recovery, request logging), `publisher.go` (RabbitMQ with reconnection), `fetchers.go` (API-specific fetch logic), `aggregator.go` (cache + poll loop), `models.go` (domain types).

3. **Security middleware**: Sets `X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`, `Referrer-Policy: strict-origin-when-cross-origin`. CORS is configurable via `COINOPS_CORS_ALLOW_ORIGIN` env var (not hardcoded `*`).

4. **Graceful shutdown**: Listens for OS signals and cleanly stops the HTTP server and background goroutines.

**Honorable mention**: **Shabat** uses `go-redis/v9` for session state management with context deadlines and graceful degradation — a pattern worth adopting. **smoliakov** has the best health check endpoint (`/healthz` with JSON status including last success/error timestamps).

---

## 3. History Service

### Approaches Across Branches

| Branch | Language | Consumer Model | API Design | Idempotency |
|:---|:---|:---|:---|:---|
| **Shabat** | Python FastAPI + separate consumer | Threaded consumer, `prefetch_count=1`, ACK after commit, NACK+requeue on error | `/health`, `/history`, `/history/{slug}`, `/prices/history/{coin}` | `ON CONFLICT DO NOTHING` |
| **hrenchevskyi** | Python Flask + consumer thread | `basic_get` polling, ACK after commit, malformed JSON → ACK (poison pill protection) | `/api/v1/history`, `/series`, `/dashboard`, `/healthz` with rich query params | `ON CONFLICT (snapshot_event_id, asset_symbol, asset_type, source) DO UPDATE` |
| **kazachuk** | Python Flask + daemon thread | `auto_ack=True` (dangerous), new connection per save | `/history?hours=`, `/favorites` (unversioned) | None |
| **kurdupel** | Go | goroutine consumer, `Nack(false, false)` for bad JSON (message lost) | `/history`, `/stats`, `/chart` with filtering/sorting/downsampling | 10-second dedup window |
| **monero-privacy-system** | Python FastAPI + asyncio worker | No queue — asyncio loop with sleep | `/stats`, `/blocks/latest`, `/privacy/*`, `/price/*`, `/trend` | SQLAlchemy `create_all` |
| **penina** | Go (consumer only, no API) | `auto_ack=True`, single INSERT | No history API in this service; Flask `ui_service` reads DB directly | None |
| **shturyn** | Python FastAPI | `auto_ack=True`, thread consumer | `/history`, `/today` | `ON CONFLICT (time) DO UPDATE` |
| **smoliakov** | Python consumer + Django reads | `prefetch_count=1`, `basic_nack(requeue=True)` on error | Django views with date filter, Redis cache | `ON CONFLICT` via unique constraint |
| **volynets** | None | None | None | None |
| **zakipnyi** | Python consumer | `prefetch_count=20`, `basic_nack(requeue=False)` on error (message lost) | FastAPI `/api/rates/latest`, `/api/rates/history/{code}` | None |

### Best Implementation: **hrenchevskyi**

**hrenchevskyi** has the most enterprise-ready history service:

1. **Strict ACK/NACK contract**: Messages are ACKed only after PostgreSQL `conn.commit()` succeeds. Malformed JSON is ACKed to prevent poison-pill infinite requeue loops. Failed inserts trigger NACK with requeue for transient errors. This is the most carefully designed delivery guarantee among all branches.

2. **Rich read API**: The `/api/v1/history` endpoint supports pagination (`limit` 1–500), the `/series` endpoint provides time-bucketed data with thinning for large datasets, and `/dashboard` returns trends with sparkline data. All endpoints are versioned under `/api/v1/`.

3. **Repository pattern**: Business logic is cleanly separated into `repository.py` (SQL queries, data enrichment), `consumer.py` (message handling), `app.py` (HTTP API), `config.py` (centralized config dataclass), `db.py` (connection pooling with `ThreadedConnectionPool`).

4. **Data enrichment**: The `_enrich_crypto_uah` method calculates UAH prices for crypto assets using the USD/UAH rate from the same snapshot — demonstrating real business logic beyond simple passthrough.

**Honorable mention**: **Shabat** uses FastAPI (better than Flask for async and automatic OpenAPI docs) with `prefetch_count=1` and the same ACK-after-commit pattern. **kurdupel** has the most feature-rich read API with stats aggregation, chart downsampling, and bucket-based queries.

---

## 4. PostgreSQL Database

### Approaches Across Branches

| Branch | Schema Complexity | Init Method | Migration Tool | Key Feature |
|:---|:---|:---|:---|:---|
| **Shabat** | 4 tables (market_snapshots, price_snapshots, whales, whale_positions) | Consumer runs `schema.sql` on startup | None | `ON CONFLICT DO NOTHING`, proper indices |
| **hrenchevskyi** | 1 table (exchange_rates) with compound unique key | Ansible Jinja2 template `init.sql.j2` | `verify_db_schema` startup check | Unique on `(snapshot_event_id, asset_symbol, asset_type, source)`, indices on time and symbol |
| **kazachuk** | 1 table (rates) | Docker entrypoint `init.sql` | None | Indices on currency and created_at |
| **kurdupel** | 1 table (currency_rates) | Ansible + Go `CREATE TABLE IF NOT EXISTS` (duplicated) | None | Duplicated DDL between Ansible and Go |
| **monero-privacy-system** | 5 tables (blocks, network_stats, price, privacy_metrics, next_block_prediction) | `schema.sql` + SQLAlchemy `create_all` (duplicated) | Alembic in requirements (unused) | Most complex domain model |
| **penina** | 1 table (rates with TEXT data column) | Go `CREATE TABLE IF NOT EXISTS` | None | Data stored as raw TEXT (not normalized) |
| **shturyn** | 1 table (weather_history) | SQL file in Docker entrypoint | None | UPSERT on unique timestamp |
| **smoliakov** | 1 table (exchange_rates) | Ansible SQL | None | `ON CONFLICT` on compound key, Django `managed=False` |
| **volynets** | None | None | None | None |
| **zakipnyi** | 1 table (currency_rates) | Vagrant provisioning `psql` | None | Indices, GRANT for app role, sequence grant |

### Best Implementation: **hrenchevskyi**

**hrenchevskyi** has the most enterprise-ready database implementation:

1. **Compound unique constraint**: `UNIQUE (snapshot_event_id, asset_symbol, asset_type, source)` prevents duplicate data at the database level while allowing the same symbol from different sources — a well-thought-out data model.

2. **Ansible-templated initialization**: The schema is defined as a Jinja2 template (`init.sql.j2`) with parameterized database name and user — ready for per-environment customization via Ansible variables.

3. **Startup schema verification**: `db.verify_db_schema()` checks for required columns (like `snapshot_event_id`) at service startup and fails fast if the schema is incompatible — a practical alternative to full migration tooling.

4. **Connection pooling**: `psycopg2.pool.ThreadedConnectionPool` with context-managed connections that properly commit or rollback — preventing connection leaks and stale transactions.

**Honorable mention**: **monero-privacy-system** has the richest domain model (5 tables with proper relationships and indices), though the dual-source DDL (SQL file + SQLAlchemy `create_all`) creates a maintenance risk. **zakipnyi** properly uses `GRANT` to restrict the application role's permissions — a good security practice that other branches skip.

---

## 5. Redis

### Approaches Across Branches

| Branch | Present? | Usage | Client | Resilience |
|:---|:---|:---|:---|:---|
| **Shabat** | Yes | UI session state (`session:{sid}`, TTL 24h) | `go-redis/v9` in Go proxy | Context timeout 2s; on failure returns 503, doesn't crash. Warning on startup if unreachable. |
| **hrenchevskyi** | Yes | Optional UI state store | Python `redis` in Flask frontend (`state_store.py`) | Reconnect cooldown (60s), `ping` on connect, client reset on error, graceful degradation |
| **kazachuk** | Yes | User favorites set | Python `redis` in consumer | Global `redis.Redis(...)`, no explicit health/reconnect |
| **kurdupel** | Yes | Flask sessions | Python `redis` in Flask UI (`SESSION_TYPE=redis`) | Default client; Ansible config has `protected-mode no` |
| **monero-privacy-system** | **No** | — | — | — |
| **penina** | Yes | Rate cache (25s TTL) in proxy | Python `redis` in Flask proxy | No graceful fallback on Redis failure |
| **shturyn** | **No** | — | — | — |
| **smoliakov** | Yes | Django view cache per date key | Python `redis` via Django cache backend | `socket_timeout=2`, `socket_connect_timeout=2`, fallback to DB on failure |
| **volynets** | **No** | — | — | — |
| **zakipnyi** | **No** | — | — | — |

### Best Implementation: **hrenchevskyi**

**hrenchevskyi** has the most enterprise-ready Redis implementation:

1. **Graceful degradation**: If Redis is unavailable, the application continues to function without state persistence. Errors are logged, the client is reset, and a cooldown (60s) prevents connection storm during outages.

2. **Connection health monitoring**: `ping` on initial connect, automatic client reset on errors, and reconnect attempt throttling.

3. **Operational safety**: Key prefix namespacing (`COINOPS_UI_STATE_PREFIX`), configurable TTL, and environment-variable-driven configuration.

**Honorable mention**: **Shabat** uses `go-redis/v9` (the more performant compiled-language client) with `context.WithTimeout` for every operation — better for high-throughput scenarios. **smoliakov** uniquely uses Redis as a proper read cache for Django views (not just session/state), which is the closest to a traditional caching pattern among all branches.

**Critical gap**: Four branches (**monero-privacy-system**, **shturyn**, **volynets**, **zakipnyi**) do not implement Redis at all, failing a core task requirement.

---

## 6. RabbitMQ

### Approaches Across Branches

| Branch | Exchange Type | Queue | Durable/Persistent | ACK Strategy | Resilience |
|:---|:---|:---|:---|:---|:---|
| **Shabat** | Default direct (`""`) | `market_events`, durable | Yes/Yes | ACK after DB commit; NACK+requeue on error | `prefetch_count=1`, infinite dial retry in Go, consumer reconnect loop in Python |
| **hrenchevskyi** | Named direct (`coinops.rates`), durable | `coinops.history`, durable | Yes/Yes | ACK after DB commit; ACK on malformed JSON (poison pill); NACK+requeue on transient error | Publisher: 5 retries with reconnect+backoff. Consumer: reconnect with exponential backoff+jitter |
| **kazachuk** | Default direct | `rates`, **not durable** | **No/No** | `auto_ack=True` | Dial retry loop; no publish retry |
| **kurdupel** | Default direct | `currency_rates`, durable | Yes/Yes (implied) | Go: `Nack(false, false)` on bad JSON (message discarded, no DLQ) | 5s reconnect loop; new connection per publish in Python |
| **monero-privacy-system** | **None** | **None** | **N/A** | **N/A** | **N/A** — uses asyncio loop instead of message queue |
| **penina** | Default direct | `rates` | Yes (queue)/Unknown (messages) | `auto_ack=True` in Go consumer | New connection per publish; basic dial retry |
| **shturyn** | Default direct | `weather_data` | Queue declared but durability unclear | `auto_ack=True` | Producer/consumer reconnect loops with sleep |
| **smoliakov** | Default direct | `nbu.exchange.rates`, durable | Yes/Yes | `prefetch_count=1`, `basic_nack(requeue=True)` on error | 5s reconnect loop; credentials mismatch (guest vs nbu_consumer) |
| **volynets** | **None** | **None** | **N/A** | **N/A** | **N/A** |
| **zakipnyi** | Named **fanout** (`rates`), durable | `rates_queue`, durable | Yes/Yes | `prefetch_count=20`, `basic_nack(requeue=False)` on error (message lost) | 30 retry attempts on dial; outer `while True` restart |

### Best Implementation: **hrenchevskyi**

**hrenchevskyi** has the most enterprise-ready RabbitMQ implementation:

1. **Named exchange**: Uses a named direct exchange (`coinops.rates`) with explicit routing key (`rates.snapshot`) — cleaner than relying on the default exchange and allows future evolution (adding more consumers, changing routing).

2. **Poison-pill handling**: The consumer distinguishes between malformed messages (ACKed to remove from queue) and transient failures (NACKed with requeue). This prevents infinite requeue loops that plague several other branches while still preserving at-least-once delivery for valid messages.

3. **Publisher resilience**: Up to 5 publish retries with reconnection and exponential backoff. Messages include a `type` header (`rates.snapshot.v1`) for consumer-side routing and versioning.

4. **Consumer resilience**: Exponential backoff with jitter for reconnection, preventing thundering herd on broker recovery.

5. **Strict delivery guarantee**: `basic_ack` is called strictly after `conn.commit()` returns — the tightest possible at-least-once guarantee without distributed transactions.

**Honorable mention**: **Shabat** implements an almost identical ACK-after-commit pattern with `prefetch_count=1` and `ON CONFLICT DO NOTHING` for idempotency. **zakipnyi** uniquely uses a **fanout exchange**, which is architecturally appropriate for broadcasting price data to multiple potential consumers — a forward-looking design choice.

**Critical gap**: **monero-privacy-system** and **volynets** have no message queue at all, fundamentally failing the async messaging requirement.

---

## Cross-Cutting Concerns

### Ansible/Terraform (Infrastructure as Code)

| Branch | Ansible | Terraform | CI/CD |
|:---|:---|:---|:---|
| **Shabat** | Full roles (common, docker, proxy, history, ui) with env templating | Hyper-V VMs + cloud-init | GitHub Actions → GHCR |
| **hrenchevskyi** | Roles with Vault-encrypted secrets, `.env.j2` templating | None | None |
| **smoliakov** | VM roles (postgres, app, web) with systemd services | AWS EC2 + SG (SSH open to world) | None |
| **kurdupel** | VM roles + Vagrant | None | None |

**Best IaC**: **Shabat** (most complete: Ansible + Terraform + CI/CD). **hrenchevskyi** has the best secrets management (Ansible Vault).

### 12-Factor App Compliance

**Best**: **hrenchevskyi** — strict `config.go` struct with fail-fast, `.env.example` with `REDACTED_BY_VAULT`, Ansible Vault for secrets, no hardcoded credentials.

**Runner-up**: **Shabat** — env files generated by Ansible, GHCR for build artifacts, but lacks the explicit fail-fast config validation.

### Observability

**Best logging library**: **monero-privacy-system** (`structlog` — the only branch using structured logging).

**Best health check**: **smoliakov** (`/healthz` returns JSON with collector status, last success/error timestamps, cycle count).

**Overall best**: No branch achieves enterprise-grade observability. All lack Prometheus metrics, OpenTelemetry tracing, and correlated request IDs across services.
