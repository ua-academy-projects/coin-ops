# Comparison Matrix — coin-ops tournament

> **Integrity caveat (updated after verification):** Shabat's `CLAUDE.md` is auto-injected as a `system-reminder` whenever any file in that worktree is read. The sub-agent analyzing Shabat echoed CLAUDE.md's one-line summary of the consumer ("Idempotent writes via `ON CONFLICT DO NOTHING`") instead of reading `consumer.py` directly. A direct re-read showed Shabat actually implements manual ACK after `db.commit()`, `nack+requeue` on failure, `prefetch_count=1` flow control, mutex-guarded AMQP publishing, regex-validated session IDs, `io.LimitReader` body caps, `json.Valid` checks, and smart NBU upstream throttling — none of which the sub-agent surfaced. Shabat's scores below have been corrected upward. The hrenchevskyi-specific caveat is minor and didn't materially change its ranking.

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
| 3 | monero-privacy-system* | 8 | 8 | 6 | 8 | 5 | 8 | 6 | 8 | 3 | 79.0 → 64.0 | **1840** |
| 4 | kazachuk | 6 | 5 | 3 | 6 | 3 | 6 | 9 | 0 | 5 | 57.5 | **1775** |
| 5 | **volynets** ‡ | 8 | 6 | 3 | 8 | 5 | 7 | 0 | 0 | 3 | 53.0 | **1730** |
| 6 | smoliakov | 6 | 8 | 3 | 6 | 3 | 6 | 0 | 4 | 3 | 50.0 | **1700** |
| 7 | shturyn | 6 | 5 | 2 | 6 | 5 | 0 | 6 | 0 | 3 | 46.0 | **1660** |
| 8 | penina | 5 | 5 | 2 | 3 | 2 | 5 | 7 | 0 | 3 | 42.0 | **1620** |
| 9 | kurdupel | 6 | 3 | 2 | 6 | 3 | 9 | 0 | 0 | 2 | 39.5 | **1595** |
| 10 | zakipnyi | 7 | 8 | 2 | 5 | 2 | 5 | 0 | 0 | 2 | 39.0 | **1590** |

† Shabat scores corrected upward after direct re-read of `proxy/main.go` and `history/consumer.py`: API robustness 6→8 (smart upstream throttling, conditional publishing, graceful fallback), Security 8→9 (input validation, body-size caps, JSON validity checks). Architecture would arguably deserve a bump too but the scale is already capped at 9 here.

\* `monero-privacy-system` receives a **−15 point component-completeness penalty** (no RabbitMQ, no Redis — two of seven required components absent). Raw score 79.0 would have placed it near #2; post-penalty it sits at 64.0 → 1840.

‡ volynets updated from "NO SUBMISSION" after new commits landed. Full implementation now present: Go proxy + Go history service + Flask UI + RabbitMQ + PostgreSQL + Ansible + Vagrant. **Redis absent** (in-process memory cache only). No Docker, no Terraform. Scores reflect actual submitted work.

### Reading the numbers

- **~150-point gap between Shabat and hrenchevskyi** (up from ~115 after the Shabat correction). In Elo terms that's roughly a 70% expected-win probability — Shabat is meaningfully, not marginally, ahead.
- **~150-point gap between hrenchevskyi and monero-privacy-system** — monero is only 3rd because of the completeness penalty; on pure pattern quality it's genuinely close.
- **Everyone from kazachuk down sits in a ~200-point band (1590–1775)** — the "everyone is mid-tier" cluster. Differences between them are real but not decisive.
- **volynets (1730)** is no longer a forfeit — it submitted a full VM-based implementation and lands at #5, above smoliakov and the rest of the mid-tier cluster. No Docker and no Terraform keep it out of the top 4 despite solid architecture scores.

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
| **kurdupel** | Coinbase | M — clean 4-VM topology, no circuit breakers | L — 5s timeout, no retries on upstream, fail-fast | L — print + log.Printf only | M — env vars + defaults, secrets in Ansible templates | L — hardcoded dev secrets, absolute SSH paths, Redis protected-mode disabled | H — Vagrant + Ansible, clean multi-VM private net, role-based | L — absent | L — absent | L — fixed IPs, no health endpoints, no discovery | **M** |
| **penina** | NBU + CoinGecko | M — clean 5-VM split but hardcoded IPs in code | M — stale-cache fallback, 5s timeout, no retries | L — print only, health checks limited | L — passwords + IPs hardcoded in source | L — credentials in app.py/main.go/definitions.json | M — Ansible playbooks, manual VM creation, hybrid Vagrant + VBox | M-H — multi-stage (Go + Node+Py), healthchecks, depends_on, no non-root | L — absent | L — single-host compose, hardcoded IPs | **M** |
| **zakipnyi** | CoinGecko + NBU | H — excellent service separation, fanout exchange, retry-on-start | H — 30-attempt retry, dual sources, conn recovery | L — basic logging only | M — env vars, but creds hardcoded in 4+ files | L — `coinops123` in Vagrantfile/README/source, CORS `*` | M — Vagrant + inline shell, hardcoded IPs, 5 VMs | — | L — absent | L — VBox-locked, no containers | **M** |
| **monero-privacy-system** | Monero RPC + CoinGecko | H — async FastAPI + SQLAlchemy, retry/backoff, graceful degradation | H — tenacity retries, CoinGecko throttling, cached fallback | M — **structlog** throughout, health endpoints, no metrics | H — Pydantic settings, env-based, `.env` templates | M — non-root containers, `*.env` gitignored, but TF state has plaintext creds, CORS `*` | H — Terraform (libvirt) + cloud-init, Alpine+OpenRC lean VMs | M — backend multi-stage + non-root, no frontend prod Dockerfile | H — best-organized TF (main/variables/outputs), cloud-init templating | L — libvirt-locked, no Helm, no StatefulSet, no managed-service story | **H** for infra, **L** for completeness |
| **volynets** ‡ | NBU | H — decoupled Go proxy + Go history + Flask UI, in-process cache-aside, graceful fallback chain | M — 2–5s timeouts, exp. backoff on RabbitMQ reconnect, parameterized SQL, no retries on NBU | L — `/health` on all services (dummy 200), plain stdlib logging, no metrics | H — all config via env vars, sensible defaults, no hardcoded IPs in app code | M — non-root (vagrant user), UFW per-service, hardcoded `guest:guest` / `coinops:coinops` as fallback defaults | H — Vagrant + Ansible (5 playbooks, idempotency guards, handlers, UFW) | — | — | L — stateless services, health endpoints, but no containers, no Helm, no cloud provider | **M** (no Docker/TF) |

---

## Critical component-coverage note

Two branches have **missing required components** from Issue #1:

- **monero-privacy-system**: no RabbitMQ, no Redis. Worker writes directly to Postgres. This is a significant gap despite the branch's otherwise strong infrastructure work — the task specifically requires async message-queue persistence.
- **shturyn**: no Redis. Otherwise complete.
- **volynets**: no Redis (in-process memory cache only). Otherwise complete — Go proxy, Go history, Flask UI, RabbitMQ, PostgreSQL, Ansible, Vagrant all present.

Every other branch implements all seven components (UI, Proxy, external API client, RabbitMQ, History Service, Postgres, Redis).

## At-a-glance summary

- **Highest overall DevOps maturity**: Shabat, hrenchevskyi, monero-privacy-system (tied, different strengths).
- **Best Docker**: Shabat (non-root + scratch + per-node compose), kazachuk (small Alpine + healthchecks).
- **Best IaC**: Shabat and monero-privacy-system (both have real Terraform, both hypervisor-locked).
- **Best messaging semantics**: hrenchevskyi (UUID event IDs + UNIQUE constraint → idempotent replay, manual ACK, jittered reconnect). Shabat is a close second: manual ACK after `db.commit()`, `nack+requeue` on failure, `prefetch_count=1`, mutex-guarded channel, `DeliveryMode: Persistent` — everything except the UUID idempotency layer.
- **Best secrets management**: hrenchevskyi (Ansible Vault + templated `.env.j2`).
- **Best observability** (relative): monero-privacy-system (only branch using structlog consistently).
- **Best API integration robustness**: hrenchevskyi and monero-privacy-system (actual exp. backoff + retry libraries).
