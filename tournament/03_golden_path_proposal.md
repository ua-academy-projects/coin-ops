# Golden Path Proposal

Actionable merge strategy and next-sprint roadmap for the coin-ops project, based on component-level analysis of all 10 non-main branches.

---

## Ranked list (ELO order)

1. **Shabat** (ELO 2135) — highest overall DevOps maturity. Full Terraform (Hyper-V) + Ansible provision/deploy playbooks, per-node Docker Compose, non-root containers on `scratch` base, runtime config injection for the UI, 12-factor throughout. Messaging layer is solid: manual ACK after `db.commit()`, `nack+requeue`, `prefetch_count=1`, mutex-guarded publishing, `DeliveryMode: Persistent`. Weak spots: no formal exp. backoff (smart NBU throttling instead), no DLQ, observability stdlib-only, Terraform Hyper-V-locked.

2. **hrenchevskyi** (ELO 1985) — highest software quality. Only branch with (a) Ansible-Vault-encrypted secrets, (b) UUID event IDs + UNIQUE constraint for idempotent replay, (c) real exponential backoff with `Retry-After` parsing, (d) ThreadedConnectionPool for Postgres, (e) graceful SIGTERM handling. No Terraform, no cloud/K8s story beyond Vagrant + docker-compose — that's why it ranks below Shabat despite strictly better application-layer code.

3. **monero-privacy-system** (ELO 1840, raw 79.0 → 64.0 after −15 penalty) — excellent Terraform (libvirt) with cloud-init templating, only branch using `structlog`, async FastAPI + SQLAlchemy async pools. **Critical gap: no RabbitMQ, no Redis** — bypasses the queue entirely and writes directly to Postgres. Strong infra patterns but fundamentally incomplete software implementation.

4. **kazachuk** (ELO 1775) — best Docker execution: multi-stage Alpine images at 23.9 MB, `depends_on: service_healthy`, rich frontend (favorites, CSV export, sparklines). Weak spots: plaintext passwords in inventory and compose, `auto_ack=True` on RabbitMQ (message loss on crash), no HTTP timeouts on upstream fetches.

5. **volynets** (ELO 1730) ‡ — late submission (previously only LICENSE). Full Go proxy + Go history service + Flask UI + RabbitMQ + PostgreSQL + Ansible (5 playbooks) + Vagrant. Architecture is clean and 12-factor compliant. Weak spots: **no Redis** (in-process memory cache only), **no Docker**, **no Terraform**, hardcoded `guest:guest` / `coinops:coinops` as credential fallbacks. Strong showing on architecture and 12-factor; disqualified as a base branch by the missing containerization and IaC.

6. **smoliakov** (ELO 1700) — only branch with AWS Terraform (however minimal), solid Go service with graceful shutdown and signal handling, comprehensive Ansible role structure, UNIQUE-constrained Postgres schema with UPSERT. Weak spots: no Docker, hardcoded passwords in playbooks, SG wide-open, `DJANGO_SECRET_KEY=replace-me-for-production`.

7. **shturyn** (ELO 1660) — cleanest React 19 frontend and most modern TypeScript stack. Proxy uses cache-aside pattern. But: **no Redis**, no VM provisioning, single-host Docker Compose only, broad CORS. Great UI cherry-picks, weak infrastructure base.

8. **penina** (ELO 1620) — best Docker learning documentation (`docs/03-docker.md` with a "Mistakes & Fixes" table is genuinely valuable as a teaching artifact). Dual VM/Docker deploy. But hardcoded credentials in source code, no Terraform, single-host Compose only, hardcoded IPs in the React app.

9. **kurdupel** (ELO 1595) — best pure VM orchestration (Vagrant + Ansible, four-VM topology, clean role separation per service), good Go history service with sophisticated time-bucketing. Critically: **no Docker at all**. Disqualified as a base; containerization-ready was an explicit acceptance criterion in Issue #1.

10. **zakipnyi** (ELO 1590) — good architecture on paper (durable fanout, Go fetcher with 30-attempt startup retry, proper indexing), but hardcoded `coinops123` in Vagrantfile + source + README + 4 other places, **no Docker**, no IaC beyond the Vagrantfile.

‡ volynets updated 2026-04-13 after new commits pushed to the branch.

---

## Recommended base: **Shabat**

### Why Shabat and not hrenchevskyi

hrenchevskyi wins more component categories — five out of eleven. But it loses the base-branch selection for three specific reasons:

1. **Shabat is containerization-complete, hrenchevskyi is not.** Shabat has four Dockerfiles (proxy, history-api, history-consumer, ui); the Go proxy uses `FROM scratch` + `USER 65532:65532`, both history services use `USER user`, and the nginx UI uses the standard nginx worker model. Per-node compose files, image pipeline to GHCR via `.github/workflows/docker-images.yml`. hrenchevskyi has Dockerfiles but the Flask frontend and history service run as root with no `USER` directive and no app-level healthchecks or image registry strategy. Closing Shabat's software gaps (by transplanting from hrenchevskyi) is a day of work. Closing hrenchevskyi's infra gaps (building the entire image + deploy pipeline) is a sprint.

2. **Shabat has Terraform, hrenchevskyi does not.** Even locked to Hyper-V, having real Terraform + cloud-init is a head-start over Vagrant + docker-compose when the next stop is AWS.

3. **Shabat has runtime config injection for the frontend.** hrenchevskyi uses Flask + Jinja2, which is fine for server-rendered pages but not what the team is moving toward (React + API). Shabat's `/docker-entrypoint.d/40-runtime-config.sh` pattern is already Kubernetes-idiomatic — one image, N environments, config from ConfigMaps/Secrets.

4. **Ansible deploy playbooks.** Shabat's `ansible/deploy.yml` orchestrates multi-node image pull, compose up, and healthcheck polling. hrenchevskyi's Ansible is strong on *provisioning* but thinner on *deployment*.

If the primary goal were pure code quality (unit-test coverage, language discipline, error handling), hrenchevskyi would win. For a DevOps internship whose next sprint is cloud + K8s, Shabat is the correct base.

---

## Cherry-pick plan

All paths below are relative to each source branch's root.

### From hrenchevskyi → replace Shabat's messaging + secrets + retry layers

These are the components where hrenchevskyi is clearly best-in-class and the transplant is mechanically straightforward.

| Target component in Shabat | Replacement from hrenchevskyi | Rationale |
|---|---|---|
| `proxy/main.go` retry loop | `services/proxy/http_retry.go` | Exponential backoff with `Retry-After` header parsing — Shabat's 10s-timeout-no-retry strategy is the weakest part of its proxy |
| `proxy/main.go` publisher | `services/proxy/publisher.go` | Mutex-protected RabbitMQ publish with UUID-keyed event IDs for idempotent delivery |
| `history/consumer.py` ack logic | `services/history_service/consumer.py` | Manual ACK only after DB commit — Shabat uses `ON CONFLICT DO NOTHING` which is correct but the ack semantics should still be tightened for poison-message handling |
| `history/db.py` pooling | `services/history_service/db.py` | ThreadedConnectionPool context manager — replaces Shabat's default psycopg2 connection per request |
| `history/schema.sql` | Merge the UNIQUE-constraint pattern from hrenchevskyi's templated schema (`snapshot_event_id` pattern) | Gives the consumer genuine idempotent-replay semantics |
| Secrets flow across all services | `infra/group_vars/all/vault.yml` + `infra/templates/.env.j2` | Replace Shabat's `.env`-rendered-by-Ansible flow with Vault-encrypted source of truth. Shabat's template structure stays; only the variable source changes |
| Ansible role layout | `infra/roles/base/` + `infra/roles/database/` patterns | Supplement Shabat's provisioning roles where hrenchevskyi's Postgres hardening (`pg_hba.conf` + SCRAM-SHA-256) is more complete |

### From monero-privacy-system → observability baseline

| Target in Shabat | Replacement | Rationale |
|---|---|---|
| Every service's logging setup | `structlog` bootstrap from `backend/core/*.py` | Only branch with JSON-ready structured logging from day one; tiny retrofit |
| `proxy/` and `history/` config loading | `backend/config.py` Pydantic `Settings` + `lru_cache` pattern | Cleaner than Shabat's ad-hoc `os.Getenv` scattering, easier to document required/optional config |
| `terraform/` structure | `terraform/main.tf` / `variables.tf` / `outputs.tf` separation + cloud-init templating | Shabat's Terraform is a 227-LOC flat file; split it along monero-privacy-system's structure before adding the AWS provider |

### From kazachuk → Docker polish

| Target in Shabat | Replacement | Rationale |
|---|---|---|
| Compose dependency ordering | `docker-compose.yml` `depends_on: {condition: service_healthy}` pattern | kazachuk has the most disciplined startup-order handling in the field |
| `proxy/Dockerfile` | `Dockerfile.proxy` pattern (23.9 MB Go image) | Size discipline — shave ~50% off Shabat's proxy image |

### From shturyn → frontend polish (optional)

| Target in Shabat | Replacement | Rationale |
|---|---|---|
| `ui/src/` components | shturyn's React 19 component tree + Recharts usage | Only if the team wants a more modern UI stack. Keep Shabat's runtime config injection regardless |

### From smoliakov → AWS Terraform starting point

| Target in Shabat | Replacement | Rationale |
|---|---|---|
| `terraform/` (post-split) | Use smoliakov's `aws_instance` + security-group definitions as scaffolding for the new AWS provider module | Don't copy wholesale — the security group is wide-open and the variables are unvalidated — but the provider wiring is a head-start |

### Explicitly reject

- **monero-privacy-system's worker-writes-directly-to-Postgres pattern.** It's simpler than RabbitMQ but violates the task requirement for async queue persistence and prevents horizontal scaling of the consumer. Keep Shabat's proxy-to-queue-to-consumer flow.
- **Any branch's hardcoded credentials.** Shabat, hrenchevskyi, and shturyn are the only three with clean secrets handling. Everything else stays out of the golden path.
- **kurdupel's Flask/Jinja2 UI.** Good for what it is, but incompatible with the React + runtime-config-injection direction.

---

## Next-sprint roadmap

Ordered from highest leverage to lowest, each item scoped to roughly one pairing-day of effort.

### Week 1 — merge the golden path

1. **Fork Shabat to a new `golden-path` branch.** Do not merge into `main` until the transplants land.
2. **Transplant the hrenchevskyi messaging layer** (proxy publisher, consumer, retry helper). Verify at-least-once semantics with a crash-injection test (`kill -9` the consumer mid-message).
3. **Transplant the hrenchevskyi Ansible Vault workflow.** Move every secret out of `.env` into `vault.yml`; delete `.env.example` fallbacks for anything sensitive; verify `git grep` returns no plaintext credentials.
4. **Transplant the `structlog` setup from monero-privacy-system.** Replace every `log.Printf` / `logger.info(...)` with a structured call. This is purely mechanical and unlocks everything downstream.
5. **Transplant hrenchevskyi's `pg_hba.conf` + SCRAM-SHA-256 auth** into Shabat's Postgres Ansible role.

### Week 2 — Ansible hardening and cloud-readiness

6. **Add app-level HEALTHCHECK directives** to every Dockerfile (not just Redis/RabbitMQ). Wire them into compose and into the future K8s liveness/readiness probes.
7. **Split Shabat's flat `terraform/` into `main.tf` / `variables.tf` / `outputs.tf`** along monero-privacy-system's pattern. No behavior change, just structure.
8. **Build an AWS provider module** alongside the existing Hyper-V one, using smoliakov's `aws_instance` definition as a starting point. Reuse the same cloud-init templates (cloud-init is provider-agnostic). Keep both providers side-by-side until AWS parity is proven.
9. **Migrate secrets from Ansible Vault to AWS Secrets Manager** via a thin lookup wrapper. This is the single largest architectural shift toward cloud-native and should be done before K8s, not after.
10. **Add a dead-letter queue** to the RabbitMQ topology. hrenchevskyi's consumer is at-least-once but has no DLQ; this is trivial to add on the exchange side and will save debugging pain on Day 1 of production.

### Week 3 — observability and metrics

11. **Add a Prometheus metrics endpoint** to the proxy and history services. Every hrenchevskyi/Shabat HTTP handler already has a logging middleware; extend it into a metrics middleware.
12. **Ship an ELK or Loki sidecar** (dev environment first, then production). Because Week 1 already migrated logging to `structlog`, this lands with almost no code changes — just log shipping config.
13. **Add correlation IDs** threaded from proxy → RabbitMQ → consumer → history API. This is the one observability piece that requires touching application code.

### Week 4 — Kubernetes groundwork

14. **Write Helm charts** for proxy, history-api, history-consumer, ui. Deployments for stateless services, a StatefulSet for Postgres (or RDS), and Redis/RabbitMQ as managed services (ElastiCache / Amazon MQ) in cloud environments.
15. **Add Kubernetes readiness and liveness probes** pointing at the existing `/health` endpoints.
16. **Externalize config via ConfigMaps and Secrets**. The runtime config injection pattern Shabat already uses for the frontend works unchanged under K8s — that was one of the reasons to pick it as the base.
17. **Set up a staging cluster on EKS/AKS/GKE** with the Helm charts and run the existing smoke tests end-to-end.

### Deferred

- CI/CD pipeline hardening (GitHub Actions already builds images for Shabat; just needs to be extended to the new topology).
- Database migrations via Alembic or Flyway (nobody has this today; Week 1 should add the tool but not the first real migration).
- Distributed tracing (OpenTelemetry): Week 3's correlation IDs are the prerequisite; actually wiring up OTel collectors is Week 5+ work.

---

## Summary

**Base: Shabat.** Transplant hrenchevskyi's messaging, secrets, and Postgres hardening onto it. Add structlog from monero-privacy-system. Cherry-pick Docker discipline from kazachuk. Build the AWS Terraform module on smoliakov's scaffolding.

The result is a branch that combines the strongest software components (hrenchevskyi) with the strongest infrastructure components (Shabat) while maintaining 12-factor compliance and containerization-readiness across the entire stack. It is ready to be the launch pad for the team's cloud + Kubernetes sprint.
