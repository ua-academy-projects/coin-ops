# Component Deep Dive

For each architectural component, this document compares how each branch approached it and names the best-in-class implementation with justification. "Best-in-class" means most ready for enterprise cloud deployment (AWS/Azure/GCP + Kubernetes + Ansible + centralized secrets + observability).

`volynets` is excluded throughout — it contains only `LICENSE`.

---

## 1. Frontend

| Branch | Stack | Build | Config injection | Notes |
|---|---|---|---|---|
| Shabat | React 18 + Vite + TS + Tailwind + Recharts | Multi-stage Node 22 → nginx:alpine | **Runtime** via `/docker-entrypoint.d/40-runtime-config.sh` generating `config.js` | Image is re-usable across environments without rebuild |
| shturyn | React 19 + TS + Recharts + Vite | Multi-stage Node → nginx | Build-time env (`BACKEND_URL`, `HISTORY_URL` in `config.ts`) | Polished UI, but image is environment-baked |
| monero-privacy-system | React 18 + Recharts | Dev-build via npm on VM | `REACT_APP_API_URL` (build-time) | No production Dockerfile |
| hrenchevskyi | Flask + Jinja2 | Python container | Env vars (PROXY_URL, HISTORY_API_URL) | Flask-Limiter, CSP headers, Redis-backed UI state with fallback |
| kazachuk | Flask + Jinja2 + vanilla JS + Chart.js | python:3.10-slim | Env vars + hardcoded defaults | Sparklines, favorites, CSV export |
| kurdupel | Flask + Jinja2 + Chart.js | venv on VM | Env vars | Session state in Redis, dark mode, 1H/24H/7D/1M ranges |
| penina | React 19 + Vite + Recharts | Multi-stage Node → Python slim | Hardcoded IPs in `App.jsx` | Service-health indicator, 30s auto-refresh |
| smoliakov | Django 5 + server-rendered SVG sparklines | Gunicorn behind nginx | Env vars | Clean, simple, Redis-cached read path |
| zakipnyi | Vanilla JS + Chart.js | Static via nginx | Hardcoded URLs | Two-tab design, interactive multi-panel charts |

**Best-in-class: Shabat.** It is the only branch whose frontend Docker image is truly 12-factor — config is injected at container start by an entrypoint script, not baked into the bundle at build time. That pattern is exactly what Kubernetes deployments want: one image, N environments, config from ConfigMaps/Secrets. shturyn's React stack is slightly more modern and the visuals are nicer, but its `BACKEND_URL` is a build-time constant, which means separate images per environment — friction under Helm values overrides or K8s promotion pipelines.

**Runner-up for UI polish:** shturyn (React 19 + Recharts) — cherry-pick the component tree if the team wants a richer UI on the Shabat base.

---

## 2. Proxy

| Branch | Language | Retry logic | Timeouts | Resilience |
|---|---|---|---|---|
| Shabat | Go | Conditional publish, last-known-value cache | 10s HTTP client | Cache-aside with RWMutex, graceful degradation on upstream 5xx |
| hrenchevskyi | Go | **5-retry exponential backoff with `Retry-After` header parsing** | Read/Write/Header timeouts configured | Graceful shutdown via SIGTERM + 10s ctx, security headers, health endpoint |
| smoliakov | Go | ctx-aware | 15s | LimitReader bounds upstream response, atomic counters |
| kurdupel | Python/Flask | — | 5s | Background thread for periodic refresh, price-smoothing |
| kazachuk | Go | Cache fallback for CoinGecko (60s TTL) | — (**no HTTP timeout**) | Goroutine pool; missing timeouts are a hang risk |
| monero-privacy-system | Nginx (static proxy) + FastAPI | — | — | Reverse proxy only; logic lives in backend |
| zakipnyi | FastAPI | — | — | CORS `*`, no retries at proxy layer |
| penina | Flask | Stale-cache fallback | 5s | Redis-backed TTL cache |
| shturyn | Go | — | 3s client | Cache-aside pattern |

**Best-in-class: hrenchevskyi.** Its proxy is the only one that implements a real production-grade HTTP retry strategy: five attempts, exponential backoff, explicit handling of `Retry-After`, and context cancellation propagation. It also wires proper `ReadHeaderTimeout` / `ReadTimeout` / `WriteTimeout` on `http.Server`, plus a clean SIGTERM handler with a 10-second drain window — both table stakes for rolling deploys and K8s pod termination grace periods. Shabat's proxy has graceful degradation and a solid cache-aside, but the retry/backoff primitives are simpler.

**Cherry-pick from hrenchevskyi:** `services/proxy/http_retry.go` and the graceful-shutdown scaffold.

---

## 3. History Service

The history service is the hardest component to get right because it combines a message consumer with a query API. This is where branches diverge most.

| Branch | Consumer semantics | Dedup strategy | Reconnect strategy | API quality |
|---|---|---|---|---|
| **hrenchevskyi** | **Manual ACK only after DB commit** (at-least-once) | **UNIQUE(snapshot_event_id, asset_symbol, asset_type, source)**; poison messages ACK'd without requeue | Jittered exponential backoff | `/api/v1/history`, `/history/series`, `/history/dashboard` with pagination-ready queries |
| Shabat | `ON CONFLICT DO NOTHING` | UNIQUE(slug, fetched_at) / UNIQUE(coin, fetched_at) | 5s constant retry | FastAPI with `/history`, `/history/{slug}`, `/prices/history/{coin}` (no pagination) |
| kazachuk | **auto-ack** (loses messages on crash) | No — duplicates possible | 5s sleep loop | Flask, LIMIT 10000 hard-coded |
| shturyn | auto-ack | UPSERT on `time` column | 5s backoff | FastAPI `/history` (last 50), `/today` |
| smoliakov | Manual ACK, signal-handling, UPSERT | UNIQUE(cc, exchange_date, collected_at) | Auto-reconnect 5s | Django read-through cache |
| kurdupel | Manual ACK | 10-second duplicate window (heuristic) | 5s backoff | Go service with time-bucketing for charts |
| penina | Auto-ack | No constraint | None | Go consumer, infinite loop |
| zakipnyi | Auto-ack | No constraint | 5s backoff | FastAPI read endpoints |
| monero-privacy-system | — (no queue) | — | — | Worker polls + writes directly to Postgres |

**Best-in-class: hrenchevskyi.** This is the only consumer in the field that gets the semantics actually right. Manual acknowledgment *after* DB commit ensures at-least-once delivery; the UNIQUE constraint on `snapshot_event_id + asset_symbol + asset_type + source` turns those into effectively-once inserts; poison messages are ACK'd without requeueing to avoid a DLQ-less replay loop. It's the single clearest "production-ready" component across all ten branches.

**Runner-ups:** smoliakov (manual ACK, batch inserts, signal handling), Shabat (solid idempotency via `ON CONFLICT DO NOTHING`).

**Cherry-pick from hrenchevskyi:** `services/history_service/consumer.py`, `services/history_service/db.py` (ThreadedConnectionPool context manager).

---

## 4. PostgreSQL Database

| Branch | Schema | Idempotency | Pooling | Auth | Migrations |
|---|---|---|---|---|---|
| **hrenchevskyi** | 1 table + indexes | UNIQUE(snapshot_event_id, ...) | **ThreadedConnectionPool (1..32)** | SCRAM-SHA-256, `pg_hba.conf` restricted to 10.10.1.0/24 | Templated SQL via Ansible Jinja2 |
| Shabat | 4 tables with UNIQUE + indexes | UNIQUE(slug, fetched_at), UNIQUE(coin, fetched_at) | Default psycopg2 | Env creds | Auto-init on consumer start |
| smoliakov | Ansible-managed, UNIQUE(cc, date, collected_at) | UPSERT on constraint | Default | Role-granted user | Playbook-applied SQL |
| kazachuk | `init.sql` with indexes | — | Default | Env creds | Raw SQL mount |
| kurdupel | 1 table NUMERIC(16), tz Europe/Kyiv | — | Default | Role-granted | Ansible SQL |
| monero-privacy-system | 5 tables, well-indexed | — | **async pool_size=10, overflow=20** (SQLAlchemy) | Env creds | Static `schema.sql`; Alembic NOT wired up despite SQLAlchemy |
| zakipnyi | 1 table NUMERIC(24,8), TIMESTAMPTZ | — | **None — new connection per request** | Env creds | `init.sql` |
| penina | 1 table `data TEXT` (!) | — | None | Hardcoded password | Go service creates schema at boot |
| shturyn | 1 table UNIQUE(time) | UPSERT on conflict | Default | Env creds | `weather_history.sql` on first boot |

**Best-in-class: hrenchevskyi.** It is the only branch that ships (a) a UNIQUE constraint designed for idempotent event replay, (b) an actual thread-safe connection pool with a context-manager API, and (c) restricted `pg_hba.conf` entries with SCRAM-SHA-256 auth. `smoliakov` and `Shabat` come close but don't pool explicitly. `monero-privacy-system` has the best connection-pool config on paper (async SQLAlchemy) but the raw SQL schema without migrations is a debt item.

**Cherry-pick from hrenchevskyi:** schema template + Ansible role that provisions users and applies `pg_hba`. From `monero-privacy-system`: index strategy for time-series tables.

---

## 5. Redis

| Branch | Purpose | Failure mode | K8s-readiness of usage |
|---|---|---|---|
| **Shabat** | Session state (`session:{sid}`, 24h TTL) | Graceful — returns 503 only on required session lookup | Stateless services; Redis is the only stateful dependency |
| hrenchevskyi | Optional UI state store | **Fallback to localStorage** on Redis failure | Truly optional — Redis outage does not break the service |
| penina | Proxy cache (25s TTL) | Stale-cache fallback | Cache pattern, reasonable |
| kurdupel | Flask session only | Protected-mode disabled (!) | Minimal use, security concern |
| smoliakov | 60s query-result cache | Graceful fallback | Clean read-through pattern |
| kazachuk | Favorites (set-based) | — | Minimal |
| zakipnyi | — | — | Not present |
| shturyn | — | — | Not present |
| monero-privacy-system | — | — | Not present |

**Best-in-class: Shabat** for the most deliberate architectural role, **hrenchevskyi** for the most resilient usage pattern. Pick Shabat if you want Redis to carry meaningful state; pick hrenchevskyi's pattern (try Redis, fall back to localStorage) if Redis is optional infrastructure.

**Cherry-pick from hrenchevskyi:** the Redis-with-fallback accessor for UI state. From smoliakov: the read-through cache wrapper in `webapp/dashboard/views.py`.

---

## 6. RabbitMQ

| Branch | Topology | Delivery mode | Ack strategy | Reconnect | DLQ |
|---|---|---|---|---|---|
| **hrenchevskyi** | **Durable direct exchange `coinops.rates` + routing key `rates.snapshot`** | Persistent | **Manual, after DB commit** | **Jittered exp. backoff** | No DLQ but poison-message handling is explicit |
| zakipnyi | Durable fanout `rates` + durable queue | Persistent | Auto-ack | 5s constant | — |
| smoliakov | Durable `nbu.exchange.rates`, batched payloads | Persistent | Manual | 5s, signal handling | — |
| kurdupel | Durable `currency_rates` | Persistent | Manual | 5s | — |
| Shabat | Single durable queue `market_events` | Persistent | (consumer) idempotent inserts, auto-routing | ctx-based | — |
| kazachuk | Durable `rates`, auto-declared at boot | — | Auto-ack | 5s sleep | — |
| shturyn | `weather_data` queue | — | Auto-ack | 5s | — |
| penina | Queue `rates`, rabbitmq definitions.json for users | — | Auto-ack | — | — |
| monero-privacy-system | — | — | — | — | — |

**Best-in-class: hrenchevskyi.** Same reason as the History Service: it is the only branch where the producer/consumer contract is explicit (durable direct exchange + routing key, persistent delivery, manual ACK after commit, jittered reconnect). Every other branch either uses `auto_ack=True` (and loses messages on consumer crash) or has no reconnect strategy at all.

**Cherry-pick from hrenchevskyi:** `services/proxy/publisher.go` (mutex-protected publisher with idempotent event IDs) and the entire consumer loop.

---

## 7. VM Provisioning

| Branch | Tool | Reproducibility | Notes |
|---|---|---|---|
| **Shabat** | **Terraform (taliesins/hyperv) + cloud-init** | High — static MACs, dynamic memory, docs for WSL/Hyper-V quirks | Gen 2 Secure Boot, documented workarounds |
| **monero-privacy-system** | **Terraform (libvirt) + cloud-init** | High — Alpine 3.19 + OpenRC, 128–256 MB VMs, network DNS | Cron-based auto-deploy every 60s |
| kurdupel | Vagrant (4 Ubuntu VMs) + Ansible roles | High — private net 192.168.56.x/24 | Clean role-per-service split |
| hrenchevskyi | Vagrant (defanator/ubuntu-24.04) + Ansible | High — 10.10.1.0/24, documented blockers | Single-node but reproducible |
| kazachuk | Bash scripts + Ansible playbooks (dual path) | Medium — hardcoded IPs, no Vagrantfile | Idempotent Ansible |
| smoliakov | Terraform (AWS EC2) + Ansible | Medium — minimal, SG open, no backend | First cloud-capable VM provisioning in the field |
| zakipnyi | Vagrant + inline shell scripts | Medium — 5 VMs, no declarative config | Works but not scalable |
| penina | Manual VirtualBox + Ansible | Low — Netplan IPs set by hand | Blockers well-documented but manual |
| shturyn | — | — | Docker-only |

**Best-in-class: Shabat.** Terraform + cloud-init, documented operational quirks, and a full Ansible deploy layer on top is the closest any branch gets to "lift-and-shift-able to a real cloud provider". **monero-privacy-system** is a close second — arguably its Terraform structure is slightly cleaner (`main.tf` / `variables.tf` / `outputs.tf` separation, cloud-init templating) — but Shabat's Ansible deployment pipeline closes the gap.

**Cherry-pick from Shabat:** `terraform/vms.tf`, `terraform/provider.tf`, ops docs (CLAUDE.md).
**Cherry-pick from monero-privacy-system:** `terraform/main.tf` cloud-init template pattern.

---

## 8. Docker / Containerization

| Branch | Multi-stage | Base image | Non-root | Healthchecks | Size discipline |
|---|---|---|---|---|---|
| **Shabat** | Yes (all 4 Dockerfiles) | Go: **scratch** (UID 65532); Python: 3.12-slim; UI: nginx:alpine | **Yes** | On all stateful services | Excellent |
| kazachuk | Yes | Alpine for Go (**23.9 MB**), slim for Python | No | On postgres/redis/rabbitmq with `depends_on: service_healthy` | Excellent |
| hrenchevskyi | Yes (all services) | Go: scratch + UPX; Python: 3.12-alpine | No | Only on Redis/RabbitMQ | Very small images |
| shturyn | Yes | Alpine/slim | No | — | Good |
| penina | Yes | python:3.10-slim, debian:bookworm-slim | No | On RabbitMQ | Good docs in `docs/03-docker.md` |
| monero-privacy-system | Yes (backend only) | python:3.11-slim | **Yes** (UID 1001) | In Dockerfile + compose | Missing frontend prod Dockerfile |
| kurdupel | — | — | — | — | No Docker |
| smoliakov | — | — | — | — | No Docker |
| zakipnyi | — | — | — | — | No Docker |

**Best-in-class: Shabat.** It is the only branch that combines (a) multi-stage builds, (b) `scratch` base for the Go proxy, (c) explicit non-root users with stable UIDs, (d) healthchecks on all stateful services, and (e) per-node compose files that actually match the Ansible deploy topology. kazachuk is a very close second — its 23.9 MB Go image and `depends_on: {condition: service_healthy}` usage is the best dependency-ordering in the field.

**Cherry-pick from kazachuk:** `docker-compose.yml` healthchecks with conditional depends_on; `Dockerfile.proxy` for the smallest Go image.
**Cherry-pick from Shabat:** the runtime config-injection entrypoint for the React frontend.

---

## 9. Terraform / IaC

| Branch | Provider | Structure | Reusability | State management |
|---|---|---|---|---|
| **monero-privacy-system** | libvirt | **main.tf / variables.tf / outputs.tf** + cloud-init templates | Medium (libvirt-locked) | Local state, no backend |
| Shabat | taliesins/hyperv | 227 LOC flat, env-driven vars | Medium (Hyper-V-locked) | Local state, no backend |
| smoliakov | **AWS** | Minimal single-file | Low (no modules, no validation) | Local state |
| hrenchevskyi | — | — | — | — |
| kazachuk | — | — | — | — |
| kurdupel | — | — | — | — |
| penina | — | — | — | — |
| shturyn | — | — | — | — |
| zakipnyi | — | — | — | — |

**Best-in-class: monero-privacy-system** for structure and templating patterns; **Shabat** for operational completeness; **smoliakov** is the only branch with an AWS provider at all.

The honest read: nobody has cloud-ready Terraform. Shabat and monero-privacy-system both have good *patterns* but are locked to their local hypervisor. smoliakov has an AWS provider but the module is too thin to be useful on its own.

**Recommended approach for the merged baseline:** take the **structure** from monero-privacy-system (`main.tf` / `variables.tf` / `outputs.tf` split, cloud-init templating), the **env-var discipline** from Shabat, and then re-target the provider to AWS using smoliakov's starting point as a reference.

---

## 10. Secrets & Configuration Management

| Branch | Approach | Vault-ready? |
|---|---|---|
| **hrenchevskyi** | **Ansible Vault (`vault.yml`) + `.env.j2` template, `.vault_pass` gitignored, SCRAM-SHA-256 DB auth** | Yes — swap Ansible Vault for HashiCorp/AWS/Azure secrets manager by changing template source |
| Shabat | `.env` gitignored, `.env.example` checked in, Ansible templates → `/etc/cognitor/*.env` mode 0640 | Yes — architecturally ready; needs Vault wiring |
| monero-privacy-system | `.env` templates, `.env.template` files, non-root containers | Partial — Terraform state still exposes plaintext passwords |
| shturyn | `.env` file (not in repo), env-file via Compose | Partial — mechanism is right, nothing hardcoded in code |
| kazachuk | **Plaintext passwords in Ansible inventory + docker-compose + defaults in code** | No |
| smoliakov | **Hardcoded in playbook vars**, `DJANGO_SECRET_KEY=replace-me-for-production` | No |
| kurdupel | **Plaintext in Ansible templates**, `SECRET_KEY=dev-secret`, SSH paths hardcoded to dev macOS home | No |
| penina | **Credentials in app.py, main.go, definitions.json, README** | No |
| zakipnyi | **`coinops123` in Vagrantfile, app.py, consumer.py, README** | No |

**Best-in-class: hrenchevskyi.** It is the only branch that (a) encrypts secrets at rest, (b) uses an idiomatic templating workflow, (c) keeps nothing in git, and (d) already has the right abstraction layer to swap Ansible Vault for an external secrets manager during the AWS migration. Shabat is the runner-up — mechanically correct, just hasn't wired Vault yet.

**Cherry-pick from hrenchevskyi:** the entire `infra/group_vars/all/vault.yml` + `infra/templates/.env.j2` workflow.

---

## 11. Observability

Every branch is in the "Low" bucket. The differences are in flavor, not quality.

| Branch | Logging | Health endpoints | Metrics / tracing |
|---|---|---|---|
| **monero-privacy-system** | **structlog** (JSON-ready) | `/health` on API + Docker healthchecks | None |
| Shabat | stdlib + `log.Printf` | `/health` on proxy + history | None |
| hrenchevskyi | Python logging + Go stdlib, request middleware | `/healthz` on proxy + history | None |
| smoliakov | stdlib, UTC timestamps | `/healthz` with timings | None |
| Others | `print()` or `log.Printf` | — | None |

**Best-in-class: monero-privacy-system.** It's the only branch that chose a structured-logging library from day one. Everything else will need a logging refactor before ELK/Loki/CloudWatch ingestion is useful. The effort to retrofit `structlog` onto Shabat/hrenchevskyi is small — but it still has to happen.

**Cherry-pick from monero-privacy-system:** the `structlog` bootstrap and the Pydantic `Settings` pattern (`backend/config.py` with `lru_cache`).

---

## Summary of best-in-class picks per component

| Component | Winner | Runner-up |
|---|---|---|
| Frontend | Shabat (runtime config injection) | shturyn (React 19 polish) |
| Proxy | hrenchevskyi (retry + Retry-After + graceful shutdown) | Shabat |
| History Service | hrenchevskyi (manual-ACK after DB commit) | smoliakov |
| PostgreSQL | hrenchevskyi (pool + SCRAM + idempotent schema) | Shabat |
| Redis | Shabat (architecturally deliberate) | hrenchevskyi (best fallback) |
| RabbitMQ | hrenchevskyi (durable exchange + routing key + manual ACK) | smoliakov |
| VM provisioning | Shabat (Terraform + Ansible deploy) | monero-privacy-system (Terraform structure) |
| Docker | Shabat (non-root + scratch + runtime config) | kazachuk (smallest images + healthcheck discipline) |
| Terraform / IaC | monero-privacy-system (structure) | Shabat (operational polish) |
| Secrets | hrenchevskyi (Ansible Vault + templates) | Shabat |
| Observability | monero-privacy-system (structlog) | — |

**Pattern:** the "software quality" components (messaging, persistence, secrets) are overwhelmingly hrenchevskyi's. The "infrastructure quality" components (Terraform, Docker, VM deployment) are overwhelmingly Shabat's. The golden path is a Shabat base with hrenchevskyi transplants.
