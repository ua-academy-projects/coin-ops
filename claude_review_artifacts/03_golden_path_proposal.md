# Golden Path Proposal — Merge Strategy for Enterprise-Ready Codebase

> **Reviewer**: Independent Senior Software Architect / DevOps Lead (Claude Opus 4.6)
> **Date**: 2026-04-13
> **Repository**: `ua-academy-projects/coin-ops`
> **Target**: A production-grade, cloud-native foundation ready for Kubernetes, Helm, CI/CD, and centralized monitoring.

---

## Executive Summary

After analyzing all 10 branches, the recommended strategy is to use **Shabat** as the infrastructure and frontend base, then surgically transplant **hrenchevskyi**'s superior application-layer resilience patterns. Selective additions from **monero-privacy-system** (observability) and **smoliakov** (health checks) round out the golden path.

**volynets** is excluded entirely (no implementation). **monero-privacy-system** is excluded as a structural base (missing Redis, RabbitMQ, separate proxy) but contributes specific patterns.

---

## 1. Base Branch: **Shabat**

### Justification

**Shabat** provides the most complete and forward-looking foundation:

| Dimension | Why Shabat |
|:---|:---|
| **Frontend** | React 19 + TypeScript + Vite with nginx serving and runtime config injection — the only "build-once, deploy-anywhere" pattern |
| **Infrastructure** | Ansible roles + Terraform + GitHub Actions CI → GHCR — most mature DevOps pipeline |
| **Container strategy** | Multi-stage Docker builds, per-node Compose files, image tagging strategy |
| **All components** | Frontend, Go proxy, Python history API + consumer, PostgreSQL, Redis (go-redis), RabbitMQ — complete task coverage |
| **Documentation** | Extensive docs (architecture, deployment, blockers, infrastructure guide, containerization plan) |

### Known Gaps in Shabat (to be addressed by cherry-picks)

1. **No HTTP retry logic** for external API calls (CoinGecko, NBU, Polymarket)
2. **No security headers middleware** in Go proxy
3. **No Ansible Vault** for secrets (uses flat env files)
4. **No structured logging** (plain `log.Printf` / Python `logging`)
5. **No config fail-fast** (inline `os.Getenv` without validation)
6. **Unused whale tables** in schema (dead code)
7. **Terraform locked to Hyper-V** (not cloud-portable)

---

## 2. Cherry-Pick Strategy (Step-by-Step)

### Step 1: Transplant API Resilience from hrenchevskyi

**Source**: `hrenchevskyi:services/proxy/http_retry.go`

**Action**: Copy `http_retry.go` into Shabat's `proxy/` directory. Refactor `fetchJSON()` in Shabat's `main.go` to route all external HTTP calls through the retry-capable client.

**What this adds**:
- Exponential backoff with jitter for transient failures
- `Retry-After` header inspection for 429 responses
- Configurable max retries and base delay
- Separate handling of network errors vs HTTP errors

**Why it matters**: Free-tier APIs (CoinGecko especially) enforce rate limits. Without this, a 429 response causes data loss for that polling cycle. With hrenchevskyi's retry logic, the proxy gracefully waits and retries.

---

### Step 2: Transplant Security & Logging Middleware from hrenchevskyi

**Source**: `hrenchevskyi:services/proxy/middleware.go`

**Action**: Adapt the middleware chain to wrap Shabat's HTTP mux. Replace Shabat's inline CORS handling.

**What this adds**:
- `X-Content-Type-Options: nosniff`
- `X-Frame-Options: DENY`
- `Referrer-Policy: strict-origin-when-cross-origin`
- Configurable CORS origin via `COINOPS_CORS_ALLOW_ORIGIN` (not hardcoded `*`)
- Panic recovery middleware (critical for Go HTTP handlers)
- Per-request logging with method, path, status, duration

---

### Step 3: Transplant Config Validation Pattern from hrenchevskyi

**Source**: `hrenchevskyi:services/proxy/config.go`

**Action**: Replace Shabat's scattered `os.Getenv()` calls with a centralized config struct that is populated and validated at startup.

**What this adds**:
- Fail-fast on missing required configuration
- Type-safe access to all config values
- Single source of truth for defaults and env var names
- Clean testability (inject config struct, not env vars)

**Integration with Shabat's Ansible**: Shabat already generates `.env` files via Ansible templates. A centralized config struct pairs perfectly — Ansible writes the env, Go validates it at startup.

---

### Step 4: Adopt Ansible Vault for Secrets from hrenchevskyi

**Source**: `hrenchevskyi:infra/group_vars/all/vault.yml` (pattern), `hrenchevskyi:infra/.env.example`

**Action**:
1. Create `group_vars/all/vault.yml` in Shabat's Ansible tree with encrypted secrets
2. Update Ansible env templates to reference vault variables
3. Create `.env.example` with `REDACTED_BY_VAULT` placeholders for documentation
4. Add `ansible-vault` commands to deployment runbook

**What this adds**:
- No plaintext secrets in the repository
- Vault password can be provided via CI/CD secret, file, or prompt
- Future migration path to HashiCorp Vault or cloud KMS

---

### Step 5: Add Structured Logging from monero-privacy-system

**Source**: `monero-privacy-system:backend/` (pattern, not direct copy)

**Action**: Add `structlog` to the Python history service and consumer. For Go, adopt a structured logger like `slog` (stdlib in Go 1.21+) or `zerolog`.

**What this adds**:
- JSON-formatted log output (ELK/Loki-ready)
- Consistent key-value pairs (timestamp, level, service, event)
- Foundation for distributed tracing (add `trace_id` to log context)

**Implementation sketch for Python**:
```python
import structlog
log = structlog.get_logger()
log.info("message_processed", slug=slug, event_type=msg_type, duration_ms=elapsed)
```

**Implementation sketch for Go**:
```go
import "log/slog"
slog.Info("fetch_complete", "api", "coingecko", "duration_ms", elapsed, "status", resp.StatusCode)
```

---

### Step 6: Add Health Check Pattern from smoliakov

**Source**: `smoliakov:Project_1/ansible/app/main.go` (`/healthz` handler pattern)

**Action**: Enhance Shabat's existing `/health` endpoint to include operational metadata.

**Target response format**:
```json
{
  "status": "ok",
  "uptime_seconds": 3600,
  "last_fetch_success": "2026-04-13T14:30:00Z",
  "last_fetch_error": null,
  "rabbitmq_connected": true,
  "redis_connected": true,
  "fetch_cycle_count": 120
}
```

**What this adds**: Kubernetes liveness/readiness probes can use this. Operations teams can monitor service health without log scraping.

---

### Step 7: Clean Up Schema Dead Code

**Action**: Remove unused `whales` and `whale_positions` tables from `history/schema.sql` unless the consumer will be updated to populate them. Dead DDL creates confusion during schema audits.

---

### Step 8: Make Terraform Cloud-Portable

**Action**: Abstract the Hyper-V-specific Terraform into a module pattern. Create parallel modules for:
- `terraform/modules/hyper-v/` (current local dev)
- `terraform/modules/azure/` (enterprise target, stub)
- `terraform/modules/aws/` (alternative, stub)

Use `terraform/main.tf` as an orchestrator that selects the module via a variable. This preserves the local development workflow while signaling enterprise readiness.

---

## 3. What NOT to Cherry-Pick (Anti-Patterns to Avoid)

| Anti-Pattern | Found In | Why to Avoid |
|:---|:---|:---|
| `auto_ack=True` in RabbitMQ consumer | kazachuk, penina, shturyn | Messages are lost if processing fails after ACK |
| `str(dict)` instead of `json.dumps()` | penina | Produces Python repr, not valid JSON — breaks downstream parsers |
| New RabbitMQ connection per publish | kurdupel, penina | Resource exhaustion under load |
| Committed binaries in git | kurdupel, smoliakov | Bloats repo, prevents reproducible builds |
| Hardcoded IP addresses in frontend | penina, kurdupel | Breaks portability; use runtime config injection instead |
| `FLASK_DEBUG=1` in production compose | hrenchevskyi | Exposes stack traces and enables debugger |
| `protected-mode no` on Redis | kurdupel | Allows unauthenticated access from any network |
| `pg_hba: host all all 0.0.0.0/0 md5` | smoliakov | PostgreSQL accessible from any IP |
| SSH `0.0.0.0/0` in Terraform Security Group | smoliakov | Public SSH access to infrastructure |

---

## 4. Final Golden Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        GOLDEN PATH                               │
├──────────────┬──────────────────────────────────────────────────┤
│ Component    │ Source                                            │
├──────────────┼──────────────────────────────────────────────────┤
│ Frontend     │ Shabat (React+TS+Vite+nginx+runtime-config)      │
│ Proxy        │ Shabat base + hrenchevskyi http_retry.go          │
│              │          + hrenchevskyi middleware.go              │
│              │          + hrenchevskyi config.go pattern          │
│              │          + smoliakov /healthz JSON pattern         │
│ History API  │ Shabat (FastAPI + versioned endpoints)            │
│ Consumer     │ Shabat base (ACK-after-commit, prefetch)          │
│              │          + hrenchevskyi poison-pill ACK pattern    │
│ PostgreSQL   │ Shabat schema (cleaned of dead tables)            │
│ Redis        │ Shabat (go-redis + graceful degradation)          │
│ RabbitMQ     │ Shabat base + hrenchevskyi named exchange pattern │
│ Logging      │ monero-privacy-system structlog pattern (Python)  │
│              │          + Go slog (stdlib)                        │
│ Secrets      │ hrenchevskyi Ansible Vault pattern                │
│ IaC          │ Shabat (Ansible+Terraform+CI) + cloud module stubs│
│ CI/CD        │ Shabat (GitHub Actions → GHCR)                    │
└──────────────┴──────────────────────────────────────────────────┘
```

---

## 5. Post-Merge Roadmap

### Phase 1: Immediate (Sprint 1)
- [ ] Execute cherry-picks (Steps 1–7 above)
- [ ] Fix `FLASK_DEBUG` removal from any compose files
- [ ] Add `.env.example` with `REDACTED_BY_VAULT` pattern
- [ ] Validate Docker builds end-to-end on all three nodes
- [ ] Write integration smoke test (curl-based: health → fetch → verify history)

### Phase 2: Containerization Hardening (Sprint 2)
- [ ] Replace per-node Compose files with a single parameterized `docker-compose.yml`
- [ ] Add Prometheus metrics endpoint to proxy (`/metrics`) and history (`/metrics`)
- [ ] Add OpenTelemetry trace propagation between proxy → RabbitMQ → consumer
- [ ] Add rate limiting to proxy (token bucket or sliding window)
- [ ] Write Dockerfile security scan step in CI (Trivy/Grype)

### Phase 3: Kubernetes Migration (Sprint 3–4)
- [ ] Create Helm chart with values.yaml per environment
- [ ] Replace Ansible env file injection with Kubernetes Secrets + ConfigMaps
- [ ] Configure HPA (Horizontal Pod Autoscaler) for proxy and consumer
- [ ] Set up Ingress controller (nginx-ingress or Traefik) to replace per-VM nginx
- [ ] Integrate with external secrets operator (HashiCorp Vault or cloud-native KMS)

### Phase 4: Production Readiness (Sprint 5+)
- [ ] Set up Grafana dashboards for proxy latency, queue depth, consumer lag
- [ ] Configure PagerDuty/Opsgenie alerts on health check failures
- [ ] Implement database migration tooling (Alembic for Python, goose for Go)
- [ ] Load testing with k6 or Locust
- [ ] Security audit: OWASP API Top 10 checklist

---

## 6. Acknowledgments

Each branch contributed something valuable to this analysis:

| Branch | Contribution to Golden Path |
|:---|:---|
| **Shabat** | Foundation: infrastructure, frontend, CI/CD, overall architecture |
| **hrenchevskyi** | Application resilience: retry logic, security middleware, config validation, Vault, poison-pill handling |
| **monero-privacy-system** | Observability pattern: structlog, tenacity, pydantic-settings |
| **smoliakov** | Health check pattern: operational JSON health endpoint |
| **zakipnyi** | Fanout exchange pattern: alternative worth documenting for broadcast scenarios |
| **kurdupel** | Rich history API: stats, charts, downsampling (consider as future feature) |
| **kazachuk** | Redis favorites: user personalization feature (consider as future feature) |
| **penina** | RabbitMQ ACL: `definitions.json` for broker-level user permissions |
| **shturyn** | TypeScript React: modern frontend approach (aligned with Shabat's choice) |
| **volynets** | (No contribution — branch not started) |
