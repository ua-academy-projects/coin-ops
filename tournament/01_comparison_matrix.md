# Comparison Matrix — coin-ops tournament

> **Integrity caveat from the prior pass:** Shabat's scores were corrected after direct source reads of `proxy/main.go` and `history/consumer.py`. The code implements manual ACK after `db.commit()`, `nack+requeue` on failure, `prefetch_count=1` flow control, mutex-guarded AMQP publishing, regex-validated session IDs, `io.LimitReader` body caps, `json.Valid` checks, and smart NBU upstream throttling.

> **2026-04-14 delta:** `origin/tsyhan`, `origin/kurdupel`, and `origin/volynets` were refreshed and re-scored from non-Markdown files only. The old `origin/monero-privacy-system` branch is now represented by `origin/tsyhan`. API topic is informational only and was not used as a penalty.

## Numeric / ELO-style scoring

Scores per category are on a 0–10 scale, with these weights applied:

| Category | Weight | Rationale |
|---|---|---|
| Architecture | 1.5 | Structural quality is load-bearing for everything else |
| API robustness | 1.0 | Single axis, important but narrow |
| Observability | 1.0 | Everyone is low; low discriminating power |
| 12-Factor compliance | 1.5 | Prerequisite for K8s migration |
| Security & secrets | 1.5 | Prerequisite for anything hitting the internet |
| VM provisioning | 1.0 | Will be rewritten in the cloud sprint regardless |
| Docker maturity | 1.5 | Direct input to Helm/K8s |
| Terraform / IaC | 1.5 | Direct input to the AWS migration |
| Cloud & K8s readiness | 1.5 | The actual target state |

Weighted total range: 0–120. Mapped to an ELO-style rating via `1200 + (weighted_total × 10)` so the spread runs 1200–2400 with the expected-draw midpoint at 1800.

**This is not real Elo** — real Elo requires pairwise matches. It's a weighted composite mapped onto an Elo-familiar number line so the gaps between branches are easy to eyeball.

| Rank | Branch | Arch | API | Obs | 12F | Sec | VM | Docker | TF | K8s | Weighted | **ELO** |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | **Shabat** † | 9 | 8 | 3 | 9 | 9 | 9 | 9 | 7 | 6 | 93.5 | **2135** |
| 2 | **hrenchevskyi** | 9 | 9 | 3 | 9 | 9 | 8 | 7 | 0 | 5 | 78.5 | **1985** |
| 3 | **tsyhan** * | 8 | 8 | 6 | 8 | 5 | 9 | 7 | 8 | 3 | 81.5 → 76.5 | **1965** |
| 4 | kazachuk | 6 | 5 | 3 | 6 | 3 | 6 | 9 | 0 | 5 | 57.5 | **1775** |
| 5 | **volynets** ‡ | 8 | 7 | 3 | 8 | 6 | 8 | 0 | 0 | 3 | 55.5 | **1755** |
| 6 | smoliakov | 6 | 8 | 3 | 6 | 3 | 6 | 0 | 4 | 3 | 50.0 | **1700** |
| 7 | shturyn | 6 | 5 | 2 | 6 | 5 | 0 | 6 | 0 | 3 | 46.0 | **1660** |
| 8 | penina | 5 | 5 | 2 | 3 | 2 | 5 | 7 | 0 | 3 | 42.0 | **1620** |
| 9 | kurdupel | 6 | 3 | 2 | 6 | 4 | 8 | 0 | 0 | 2 | 40.0 | **1600** |
| 10 | zakipnyi | 7 | 8 | 2 | 5 | 2 | 5 | 0 | 0 | 2 | 39.0 | **1590** |

† Shabat scores corrected upward after direct re-read of `proxy/main.go` and `history/consumer.py`: API robustness 6→8 (smart upstream throttling, conditional publishing, graceful fallback), Security 8→9 (input validation, body-size caps, JSON validity checks). Architecture would arguably deserve a bump too but the scale is already capped at 9 here.

\* `tsyhan` no longer gets the old "no RabbitMQ / no Redis" component penalty: both services are now present in Docker Compose and Terraform/cloud-init. It still receives a smaller architecture penalty because RabbitMQ is used as a notification channel after the worker writes to PostgreSQL, not as the async persistence boundary with ACK-after-commit consumer semantics.

‡ volynets updated again after new commits landed. Full implementation remains VM/systemd based, now with root-only env files, Gunicorn, restart handlers, graceful shutdown in Go services, and better chart/history modes. **Redis absent** (in-process memory cache only). No Docker, no Terraform.

### Reading the numbers

- **~150-point gap between Shabat and hrenchevskyi** (up from ~115 after the Shabat correction). In Elo terms that's roughly a 70% expected-win probability — Shabat is meaningfully, not marginally, ahead.
- **~20-point gap between hrenchevskyi and tsyhan** — tsyhan is now genuinely close on overall DevOps score because of Terraform, Docker Compose, Redis/RabbitMQ, and observability. hrenchevskyi still wins software reliability because its queue is actually the persistence boundary.
- **Everyone from kazachuk down sits in a ~200-point band (1590–1775)** — the "everyone is mid-tier" cluster. Differences between them are real but not decisive.
- **volynets (1755)** keeps #5 and is now the strongest VM/Ansible reference below the container/IaC-heavy top four. No Docker and no Terraform keep it out of the top 4 despite better operational polish.

---

Scope: 10 non-main branches of `ua-academy-projects/coin-ops`, evaluated against Issue #1 ("public data viewer with history") for a DevOps internship moving toward cloud/K8s deployment.

Ratings: **H** = High, **M** = Medium, **L** = Low, **—** = absent / not applicable.

API topic is informational only. It was **not** used as a scoring factor — the task explicitly permits currency, crypto, commodity, or weather APIs.

| Branch | API topic | Architecture | API robustness | Observability | 12-Factor | Security & secrets | VM provisioning | Docker | Terraform / IaC | Cloud & K8s readiness | Overall DevOps maturity |
|---|---|---|---|---|---|---|---|---|---|---|---|
| **Shabat** | Polymarket + CoinGecko + NBU | H — decoupled proxy→queue→history, cache-aside, idempotent inserts, mutex-guarded publishing, manual ACK after commit, nack+requeue on failure, prefetch_count=1 | M — 10s timeouts, smart NBU throttle (1-hr gate + failure suppression), conditional price publishing, graceful fallback; no formal exp. backoff or DLQ | L — stdlib logs only, no metrics/tracing | H — env-only config, runtime-injected UI config | H — no hardcoded creds, non-root containers, UFW, SSH keys, regex-validated session IDs, io.LimitReader body caps, json.Valid checks | H — Terraform + cloud-init + Hyper-V, documented quirks | H — multi-stage + scratch base + non-root + per-node compose | M — Terraform exists but Hyper-V-only, flat structure | M — stateless services portable, but Compose/TF not K8s-native | **H** |
| **hrenchevskyi** | NBU + CoinGecko | H — idempotent events (UUID + UNIQUE), graceful shutdown, pools | H — 5-retry exp. backoff, Retry-After parsing, ctx cancel | L — stdout only, no JSON/metrics/tracing | H — all config env-driven, no hardcoded secrets | H — Ansible Vault + .env.j2, SCRAM-SHA-256, security headers | H — Vagrant + Ansible, idempotent, documented | M — multi-stage + scratch, but runs as root, no app HEALTHCHECK | L — absent | M — 12-factor ready, but no Helm/StatefulSet, Postgres on VM | **H** |
| **kazachuk** | NBU + CoinGecko | M — clean separation, missing circuit breakers/timeouts on upstream | M — cache fallback on CoinGecko, no retries on NBU, no HTTP timeouts | L — print statements, no correlation IDs | M — env vars used, but defaults embed infra | L — plaintext passwords in inventory + docker-compose | M — dual Bash + Ansible, hardcoded IPs, no Vagrantfile | H — multi-stage Alpine, 23.9 MB Go image, healthchecks, depends_on conditions | L — absent | M — portable images, env-driven, but no Helm/probes | **M** |
| **smoliakov** | NBU | M — multi-tier sound, async via MQ, hardcoded topology | H — 15s timeout, ctx-aware, error classification, LimitReader | L — `/healthz` only, no metrics/tracing | M — env-driven, but passwords in playbooks | L — hardcoded creds in Ansible, SG open 0.0.0.0/0 | M — basic Terraform on AWS + Ansible, no validation/backend | L — absent | M — basic AWS Terraform, minimal, no modules | L — no containers, no Helm, VM-centric | **M** |
| **shturyn** | Open-Meteo (weather) | M — clean proxy/history split, cache-aside, hardcoded service names | M — free API, no retries, client-only timeout | L — print/log statements, no probes | M — env vars via compose, `.env` not in repo | M — secrets in external `.env`, broad CORS, no TLS | — | M — multi-stage alpine+nginx, but no healthchecks/limits/non-root | — | L — hardcoded hostnames, no probes/manifests | **M-L** |
| **kurdupel** | Coinbase | M — clean 4-VM topology, no circuit breakers | L — 5s timeout, no retries on upstream, fail-fast | L — print + log.Printf only | M — env vars + Ansible templates | L-M — Ansible Vault exists, but absolute SSH key paths, `/vagrant` runtime, Redis protected-mode disabled | H — Vagrant + Ansible roles for all services, private net | L — absent | L — absent | L — fixed IPs, no image artifacts, no discovery | **M** |
| **penina** | NBU + CoinGecko | M — clean 5-VM split but hardcoded IPs in code | M — stale-cache fallback, 5s timeout, no retries | L — print only, health checks limited | L — passwords + IPs hardcoded in source | L — credentials in app.py/main.go/definitions.json | M — Ansible playbooks, manual VM creation, hybrid Vagrant + VBox | M-H — multi-stage (Go + Node+Py), healthchecks, depends_on, no non-root | L — absent | L — single-host compose, hardcoded IPs | **M** |
| **zakipnyi** | CoinGecko + NBU | H — excellent service separation, fanout exchange, retry-on-start | H — 30-attempt retry, dual sources, conn recovery | L — basic logging only | M — env vars, but creds hardcoded in 4+ files | L — `coinops123` in Vagrantfile/source, CORS `*` | M — Vagrant + inline shell, hardcoded IPs, 5 VMs | — | L — absent | L — VBox-locked, no containers | **M** |
| **tsyhan** | Monero RPC + CoinGecko | H — async FastAPI + SQLAlchemy, retry/backoff, Redis sessions; RabbitMQ is notification-only | H — tenacity retries, CoinGecko throttling, cached fallback | M — **structlog** throughout, health endpoints, no metrics | H — Pydantic settings, env-based, `.env` templates | M — non-root backend container, `*.env` gitignored, but demo creds/CORS and TF state risks remain | H — Terraform (libvirt) + cloud-init, Alpine+OpenRC VMs for app/db/redis/rabbitmq | M — backend multi-stage + non-root, full dev compose, no frontend prod Dockerfile | H — best-organized TF (main/variables/outputs), cloud-init templating | L — libvirt-locked, no Helm, no StatefulSet, no managed-service story | **H** for infra, **M** overall |
| **volynets** ‡ | NBU | H — decoupled Go proxy + Go history + Flask UI, in-process cache-aside, graceful fallback chain | M-H — 2–5s timeouts, exp. backoff on RabbitMQ reconnect, graceful shutdown, parameterized SQL, no retries on NBU | L — `/health` on services, plain stdlib logging, no metrics | H — app config via env vars, root-only runtime env files in Ansible | M-H — UFW per-service and generated env files; demo `.env.example` values remain | H — Vagrant + Ansible (5 playbooks, idempotency guards, handlers, UFW) | — | — | L — stateless services, health endpoints, but no containers, no Helm, no cloud provider | **M** (no Docker/TF) |

---

## Critical component-coverage note

Component coverage caveats after the 2026-04-14 refresh:

- **tsyhan**: Redis and RabbitMQ are now present, so the old component-absence penalty is removed. The remaining issue is semantic: the worker writes directly to Postgres and publishes RabbitMQ notifications afterward, so RabbitMQ is not the async persistence boundary.
- **shturyn**: no Redis. Otherwise complete.
- **volynets**: no Redis (in-process memory cache only). Otherwise complete — Go proxy, Go history, Flask UI, RabbitMQ, PostgreSQL, Ansible, Vagrant all present.

Every other branch implements all seven components (UI, Proxy, external API client, RabbitMQ, History Service, Postgres, Redis).

## At-a-glance summary

- **Highest overall DevOps maturity**: Shabat, hrenchevskyi, tsyhan (different strengths).
- **Best Docker**: Shabat (non-root + scratch + per-node compose), kazachuk (small Alpine + healthchecks).
- **Best IaC**: Shabat and tsyhan (both have real Terraform, both hypervisor-locked).
- **Best messaging semantics**: hrenchevskyi (UUID event IDs + UNIQUE constraint for idempotent replay, manual ACK, jittered reconnect). Shabat is a close second: manual ACK after `db.commit()`, `nack+requeue` on failure, `prefetch_count=1`, mutex-guarded channel, and persistent delivery.
- **Best secrets management**: hrenchevskyi (Ansible Vault + templated `.env.j2`).
- **Best observability** (relative): tsyhan (only branch using structlog consistently).
- **Best API integration robustness**: hrenchevskyi and tsyhan (actual exp. backoff + retry libraries).
