# Branch-by-Branch Comparison

This file covers all 11 inspected branches, including `main` and `volynets`.

2026-04-14 delta recheck: `origin/tsyhan`, `origin/kurdupel`, and `origin/volynets` were refreshed and re-evaluated from non-Markdown files only. Participant README/report Markdown files were ignored. API topic itself is not treated as a disqualifier; the analysis focuses on service boundaries, persistence, queueing, reproducibility, and deployment maturity.

## `origin/Shabat`

### Summary

Three-VM distributed Polymarket dashboard. The branch contains React/Vite UI, Go live proxy, FastAPI history API, Python RabbitMQ consumer, PostgreSQL, RabbitMQ, Redis, per-node Docker Compose files, Ansible provisioning/deployment roles, Hyper-V Terraform with cloud-init, and a GHCR build workflow.

### Strengths

- Best overall architecture fit for the current repository: UI, live proxy, async persistence, history API, queue, database, and cache are separated cleanly.
- Stronger deployment pipeline than the other branches: GitHub Actions builds images, Ansible deploys image tags, and VMs do not need application source at runtime.
- Docker maturity is high for this tournament: multi-stage Go/UI builds, non-root Python containers, official Postgres/RabbitMQ/Redis images, Compose dependency health checks, and host-mounted persistent data.
- Terraform is real infrastructure code for the local VM target, not just notes: static IPs, Hyper-V VM resources, generated cloud-init seed ISOs, and useful outputs.
- Ansible is structured into roles, templates secrets into `/etc/cognitor`, installs Docker, opens expected ports, starts Compose stacks, probes health endpoints, and prunes dangling images.
- The consumer has a better reliability pattern than most branches: durable queue, prefetch, ack after database commit, nack/requeue on failure, idempotent inserts.

### Weaknesses

- Terraform is tightly coupled to local Hyper-V, WSL, WinRM, Windows paths, and `null_resource`/local-exec flows. It is useful now but not reusable as AWS infrastructure.
- No automated test suite is present for UI, Go proxy, Python services, deployment, or infrastructure.
- No Kubernetes manifests, Helm chart, ECS task definitions, or AWS Terraform modules.
- Some deployment artifacts still reflect the older systemd/source-sync path while the current playbooks use GHCR plus Docker Compose.
- `community.general.ufw` is used but no Ansible collection requirements file is committed.
- `.terraform.lock.hcl` is ignored, which weakens provider reproducibility.
- Custom application containers do not define Dockerfile-level `HEALTHCHECK`; health is mostly enforced externally through Ansible.

### Risks / Technical Debt

- Single-node stateful services are SPOFs: PostgreSQL, RabbitMQ, Redis, and the history API/consumer are not highly available.
- UFW opens service ports by port number but does not restrict all of them by source security boundary.
- Runtime secrets are host env files. That is acceptable for demo VMs but should move to a secret manager or orchestrator secret backend.
- External API dependencies are unauthenticated public APIs with likely rate limits.
- Database migrations are embedded in service startup/schema SQL rather than managed by a migration tool.
- No observability stack: no metrics, tracing, alerting, centralized logs, SLOs, or dashboards.
- No backup/restore workflow for PostgreSQL or RabbitMQ state.

### Missing For Production

- AWS VPC/networking, IAM, security groups, managed database/cache/queue choices, TLS, DNS, remote Terraform state, and environment separation.
- CI checks for lint, tests, image build, image scan, Terraform validation, Ansible linting, and Compose smoke tests.
- Immutable release promotion and rollback runbook.
- Secrets management through AWS Secrets Manager/SSM, Vault, or Kubernetes Secrets with an external secret backend.
- Database migrations, backups, restore tests, and retention policy.
- Kubernetes readiness probes, liveness probes, resource requests/limits, HPA, PodDisruptionBudgets, and Helm/Kustomize.

### Recommended Improvements

- Use this as the baseline.
- Remove or isolate stale systemd-era deployment artifacts.
- Add `ansible/requirements.yml` and pin collections.
- Commit Terraform lock files for real environments.
- Add root-level local Compose for developers while keeping per-node Compose for VM deployment.
- Add CI for UI/Go/Python/build/security/IaC checks.
- Start AWS Terraform as a separate module tree while preserving the working Hyper-V demo.
- Add health checks, structured logging, metrics, backup runbooks, and release rollback procedures.

## `origin/hrenchevskyi`

### Summary

Currency/exchange-rate implementation with a Go proxy, Python history service, Flask frontend, Redis, RabbitMQ, Docker Compose for most services, and a Vagrant/Ansible database VM. It uses Ansible Vault for database secrets and has a clear runbook.

### Strengths

- Clean service code compared with most branches: config validation, request timeouts, security headers, rate limiting, same-origin history proxying, Redis-backed UI state, and structured history API endpoints.
- Dockerfiles use multi-stage builds and relatively small images.
- Docker Compose has health checks for RabbitMQ and Redis and uses service-name networking.
- Ansible database role is understandable and uses variables plus Vault.
- Documentation is honest about hybrid Docker plus VM topology and includes smoke tests.

### Weaknesses

- Infrastructure is hybrid local Docker plus one Vagrant database VM, not a full multi-node deployment.
- No Terraform and no CI workflow.
- Compose builds locally on the target instead of deploying immutable registry images.
- PostgreSQL remains outside Compose and outside managed cloud primitives.
- The sample `.env.example` includes weak demo passwords and inline comments that may be unsafe for dotenv parsing.
- Containers mostly run as root and do not include runtime health checks for custom app services.

### Risks / Technical Debt

- The branch is less aligned with the current Polymarket/dashboard shape of `origin/Shabat`.
- Local Vagrant database topology does not map cleanly to AWS or Kubernetes.
- Deployment depends on operator sequencing: `vagrant up`, then `docker compose up`.
- No automated verification or reproducible CI artifact.

### Missing For Production

- Full IaC for all runtime services.
- Image registry and immutable tags.
- Managed secrets, TLS, monitoring, backups, and rollback.
- Automated tests and pipeline gates.
- Kubernetes manifests or cloud-native deployment definitions.

### Recommended Improvements

- Reuse selected application patterns: fail-fast config, security headers, rate limiting, and clearer runbook style.
- Replace the hybrid topology with either a fully local Compose stack or a real cloud architecture.
- Add CI image builds and push to a registry.
- Add Terraform modules for cloud networking and service dependencies.

## `origin/kazachuk`

### Summary

Currency and crypto rates system with two deployment modes: four VM systemd deployment via Ansible and a single-host Docker Compose stack with frontend, Go proxy, consumer/history API, RabbitMQ, PostgreSQL, and Redis.

### Strengths

- One of the more complete app implementations after `Shabat`.
- Supports both VM deployment and Docker deployment.
- Docker Compose includes full stack dependencies, named Postgres volume, health checks for Postgres/RabbitMQ/Redis, and service-name networking.
- Custom Dockerfiles use multi-stage builds and Alpine/slim images.
- Application config can be overridden through environment variables.
- Service layout and automation make the dual VM/Docker intent visible from code and config.

### Weaknesses

- Hardcoded credentials appear in Compose, Ansible, and source defaults.
- No Terraform, no CI, no registry deployment, and no cloud path.
- RabbitMQ queue/publish settings in the proxy are non-durable in places, and the consumer uses `auto_ack=True`, so messages can be lost on crash or failed database write.
- Database, Redis, and RabbitMQ ports are exposed broadly in Docker mode.
- VM Ansible playbooks clone from GitHub and force branch state on each VM, which is less controlled than image-based deployment.

### Risks / Technical Debt

- Data loss risk due to weak message durability and early acknowledgements.
- Demo credentials could accidentally leak into non-demo deployments.
- Manual image build steps do not provide immutable or reproducible release artifacts.
- No separation of local, staging, and production configuration.

### Missing For Production

- Secret management, durable queue contract, transaction-safe acking, TLS, source-restricted network policy, backups, monitoring, and tests.
- Terraform AWS modules and remote state.
- Kubernetes manifests or Helm chart.

### Recommended Improvements

- Move all credentials to `.env.example` plus secret backend.
- Make queue and messages durable and ack only after successful database commit.
- Add registry image builds and immutable tags.
- Add Terraform for the current VM topology or jump straight to AWS modules.
- Pull Compose health-check patterns into the unified baseline.

## `origin/tsyhan`

### Summary

Formerly evaluated as `origin/monero-privacy-system`. The refreshed `origin/tsyhan` branch is a Monero/privacy analytics implementation with React frontend, FastAPI backend, worker, PostgreSQL, Redis-backed sessions, RabbitMQ, local Docker Compose, Alpine/OpenRC deploy scripts, and libvirt Terraform with cloud-init. The API topic is not the issue; the important caveat is that RabbitMQ is not used as the persistence boundary. The worker writes directly to PostgreSQL and publishes a notification event afterward.

### Strengths

- Strongest standalone Terraform/cloud-init experiment outside `Shabat`.
- Terraform models network, static IPs, VM disks, cloud-init disks, variables, and outputs.
- Cloud-init now models separate frontend, backend, database, Redis, and RabbitMQ VMs.
- Local Docker Compose now includes PostgreSQL, Redis, RabbitMQ, API, worker, and frontend services.
- FastAPI uses Pydantic settings, async SQLAlchemy, Redis session storage, health endpoint, and structured logging through `structlog`.
- Docker backend runs as non-root and includes a health check.
- Price fetching has retry/backoff and cached fallback behavior.

### Weaknesses

- RabbitMQ is present but notification-only: there is no queue-backed history consumer, no ACK-after-commit persistence flow, and no DLQ.
- Production deploy model uses cron polling from Git every minute, which is not a controlled release mechanism.
- `terraform/variables.tf` still defaults `deploy_branch` to `monero-privacy-system`, which no longer exists as a remote branch after pruning.
- Terraform is libvirt/KVM specific, not AWS.
- Docker coverage is incomplete for production: backend image exists, but frontend is a dev-server container and there is no registry release path.
- Defaults include demo credentials and a broad CORS posture.
- No CI, no image registry deployment, no Kubernetes manifests.

### Risks / Technical Debt

- Direct database writes from the worker bypass the queue semantics the team should keep for scalable ingestion.
- Auto-deploy from branch state can deploy unreviewed or broken commits.
- Terraform state would contain secrets rendered into cloud-init.
- Small VM sizes and Alpine/OpenRC assumptions may not represent the team target.
- The branch rename/default mismatch can break fresh VM deploys unless `deploy_branch` is overridden.

### Missing For Production

- Queue-backed persistence with manual ACK after database commit.
- Controlled release pipeline, rollback, monitoring, TLS, backups, cloud-managed dependencies, and secret management.
- AWS modules and Kubernetes packaging.

### Recommended Improvements

- Do not use as the baseline.
- Reuse the clearer cloud-init structure, Terraform outputs, Pydantic settings, and `structlog` patterns when building the unified baseline.
- If the team wants to mine the Docker Compose work, keep the service set but replace the frontend dev server with a production image and add health-gated dependencies.
- Replace cron-pull deployment with CI/CD-controlled image promotion.
- Move RabbitMQ in front of persistence or treat its current event stream as a notification bus only.

## `origin/penina`

### Summary

Five-VM currency dashboard design with Flask/React UI, Python proxy, RabbitMQ, Go history service, PostgreSQL, Redis, Ansible playbooks, and a Docker Compose attempt.

### Strengths

- Clear five-VM service split is visible from the committed service directories and automation files.
- Documents real operational blockers and learning around Docker, RabbitMQ definitions, Redis caching, and image size.
- Includes separate service directories and a RabbitMQ definitions file.
- Attempts both systemd VM deployment and Docker Compose.

### Weaknesses

- Docker Compose build paths do not match committed directories (`./proxy`, `./history`, `./ui` under `docker/` are not present).
- Ansible playbooks reference missing `ansible/files/...` sources.
- Credentials and IPs are hardcoded in playbooks, Compose, and source.
- No Terraform, no CI, and no registry.
- Systemd and Docker automation drift apart.

### Risks / Technical Debt

- Not reproducible from the committed tree without reconstructing missing files or fixing paths.
- Hardcoded secrets make non-demo use unsafe.
- Manual VM creation and host-specific IPs block cloud migration.
- RabbitMQ and database code are demo-level and lack robust ack/retry/idempotency.

### Missing For Production

- Working automation, externalized configuration, secret management, durable messaging, tests, cloud IaC, monitoring, backups, and Kubernetes packaging.

### Recommended Improvements

- Fix repository layout and Compose build contexts first.
- Replace hardcoded credentials/IPs with environment templates.
- Consolidate runnable commands after the automation paths are fixed.
- Use as a learning artifact, not as baseline.

## `origin/zakipnyi`

### Summary

Nested `coin-ops/` project with a five-VM Vagrant deployment: nginx static UI, FastAPI backend, Go API getter, RabbitMQ, Python history consumer, and PostgreSQL.

### Strengths

- Closely follows the original VM-based requirement with five clearly separated roles.
- Single `vagrant up` can provision the full demo topology.
- RabbitMQ uses a durable fanout exchange and the consumer acks after database insert.
- Database schema and API endpoints are simple and understandable.
- nginx proxies UI `/api/` calls to backend.

### Weaknesses

- No Docker, no Terraform, no Ansible, no CI.
- Provisioning is embedded in a large Vagrantfile with shell scripts.
- Credentials and fixed IPs are hardcoded throughout Vagrant and source defaults.
- Uses Ubuntu 22.04 instead of the newer Ubuntu 24.04 target used by stronger branches.
- No robust secret handling, migrations, tests, or image artifacts.

### Risks / Technical Debt

- Cloud migration would require rewriting nearly all deployment automation.
- State, backups, TLS, monitoring, and rollback are absent.
- Nested repository layout makes integration with the current repo awkward.
- Shell provisioning can drift and is harder to lint/test than Ansible/Terraform.

### Missing For Production

- Containerization, cloud IaC, secrets, TLS, monitoring, backups, CI, tests, and Kubernetes-ready deployment definitions.

### Recommended Improvements

- Extract the useful five-role VM topology as a reference only.
- Convert services to Docker images and move provisioning out of shell blocks.
- Externalize all credentials and IPs.

## `origin/smoliakov`

### Summary

`Project_1/` contains Vagrant three-VM setup, Ansible playbooks for PostgreSQL, RabbitMQ/Go collector, Django/nginx/Redis dashboard, and a minimal AWS Terraform example.

### Strengths

- Attempts both local VM automation and AWS Terraform.
- Uses Ansible to install services and configure systemd/nginx/PostgreSQL.
- Contains a web application, queue consumer, database, and collector flow.

### Weaknesses

- Commits local `.vagrant` metadata, application binary, logs, and `terraform.tfvars`.
- Hardcoded passwords are present in Ansible and service environment files.
- AWS Terraform creates only one EC2 instance plus a security group with SSH open to `0.0.0.0/0`.
- No Docker and no image build/deploy workflow.
- Repository layout is isolated under `Project_1/` and does not align with the main project structure.

### Risks / Technical Debt

- Severe repo hygiene and security issues.
- Terraform is not reusable as production AWS infrastructure.
- PostgreSQL is opened broadly in playbooks.
- App and deployment are too divergent for easy team baseline use.

### Missing For Production

- Clean repository state, secret management, real AWS network design, Docker, CI, tests, TLS, backups, observability, and Kubernetes path.

### Recommended Improvements

- Remove generated artifacts and secrets from history before reuse.
- Rebuild Terraform around VPC/subnets/security groups/instances or managed services.
- Dockerize services and replace hardcoded environment values.

## `origin/kurdupel`

### Summary

Four-VM Vagrant/VirtualBox implementation with Flask UI, Flask proxy, Go history service, PostgreSQL, RabbitMQ, Redis, and Ansible roles for each service. The 2026-04-14 update makes it a real VM/Ansible implementation rather than the earlier partial scaffold, but it still has no Docker, Terraform, CI, registry, or cloud migration path.

### Strengths

- Clear four-VM split: UI, proxy, history, and data services.
- Ansible now has a role-per-service structure: common packages, PostgreSQL, RabbitMQ, Redis, proxy, history, and UI.
- systemd unit templates exist for UI, proxy, and history services with environment-driven host/password values.
- RabbitMQ queue is durable and proxy publishes persistent messages.
- UI uses Redis-backed Flask sessions.
- Go history service has useful chart/history query logic, including range windows and downsampling.

### Weaknesses

- No Docker, Terraform, CI, or registry.
- Inventory contains host-specific absolute private-key paths under a local macOS home directory.
- Runtime code is executed from `/vagrant`, so deployment is tied to the Vagrant shared folder rather than a release artifact.
- PostgreSQL setup uses multiple shell/psql blocks instead of idempotent PostgreSQL Ansible modules.
- Redis protected mode is disabled for the private network.
- Proxy still has no retry/backoff around the upstream API and limited failure isolation.

### Risks / Technical Debt

- It is reproducible mainly on the original author's local Vagrant/VirtualBox path unless inventory paths are fixed.
- The Go consumer calls `saveToDB`, but `saveToDB` only logs insert errors and does not return failure to the consumer; the message is ACKed even when the insert failed.
- Several JSON paths use unchecked type assertions, so malformed queue messages can panic the consumer.
- RabbitMQ, Redis, and PostgreSQL are co-located on one data VM, which is fine for a demo but not a scalable state boundary.
- No immutable artifact or rollback model exists.

### Missing For Production

- Docker images, image registry, and cloud IaC.
- CI checks, tests, Ansible linting, and reproducible release artifacts.
- Proper secrets manager integration, TLS, backups, monitoring, and Kubernetes packaging.
- Better poison-message handling and ACK-after-confirmed-write behavior.

### Recommended Improvements

- Treat as a VM/Ansible learning reference, not as the team baseline.
- Replace absolute inventory key paths with portable Vagrant inventory generation.
- Make `saveToDB` return an error and ACK only after confirmed database success.
- Replace shell SQL provisioning with PostgreSQL Ansible modules.
- Containerize the services before any AWS/Kubernetes work.

## `origin/shturyn`

### Summary

Small React/Vite frontend and Go weather proxy. The weather API topic is not a disqualifier by itself, but the branch contains no meaningful database, queue, cache, VM, Terraform, Ansible, or CI implementation for the tournament architecture.

### Strengths

- Minimal frontend/backend split exists.
- Frontend has Vite/TypeScript project scaffolding.

### Weaknesses

- No database, queue, cache, VM deployment, Docker, Terraform, Ansible, or CI.
- Hardcoded backend URL in frontend config.

### Risks / Technical Debt

- Cannot serve as a baseline for the requested project.

### Missing For Production

- All required Coin-Ops application and infrastructure capabilities.

### Recommended Improvements

- Restart from the shared baseline branch rather than evolving this branch.

## `origin/main`

### Summary

Initial repository state with only the MIT license.

### Strengths

- Clean starting point.

### Weaknesses

- No implementation.

### Risks / Technical Debt

- No application or infrastructure to evolve.

### Missing For Production

- Everything beyond the license.

### Recommended Improvements

- Keep only as repository base/history reference.

## `origin/volynets`

### Summary

Rechecked after the 2026-04-14 remote refresh. `origin/volynets` is a real five-VM exchange-rate tracker with Flask/Jinja UI, Go API proxy, Go history service, RabbitMQ, PostgreSQL, Vagrant VM creation, and Ansible provisioning. The latest commits add operational hardening: root-owned env files, restart handlers, Gunicorn for the UI, graceful shutdown in the Go services, and richer chart modes. It is a strong VM/systemd implementation but still has no Docker, Terraform, CI, registry-based delivery, or Redis.

### Strengths

- Clean five-VM service split: web UI, API proxy, database, message queue, and history service.
- Good Ansible coverage with separate playbooks for PostgreSQL, RabbitMQ, history service, proxy, and web UI.
- Uses environment variables for deployment secrets in Ansible and writes runtime env files under `/etc/coin-ops` with root-only permissions.
- UFW rules are more deliberate than many branches: PostgreSQL and RabbitMQ are source-restricted to expected service hosts.
- Go proxy has in-memory caching, history-service fallback, `/health`, CORS configuration, and RabbitMQ reconnect with exponential backoff.
- Go proxy and history service now include graceful SIGINT/SIGTERM shutdown paths.
- Go history service has a solid consumer pattern: durable queue, manual ack after transaction commit, transaction per batch, upsert with `ON CONFLICT`, nack/requeue on transient database failures, and reconnect loop.
- Database schema is simple but practical, with indexes and a unique `(code, rate_date)` key for idempotency.
- Web UI now runs with Gunicorn under systemd and includes more useful chart/history display modes.

### Weaknesses

- No Dockerfiles or Docker Compose.
- No Terraform, cloud IaC, CI/CD pipeline, image registry, or immutable release artifact.
- Vagrant is VMware Desktop-specific, which reduces portability across teammates compared with VirtualBox/Hyper-V-neutral options.
- Ansible builds Go binaries directly on target VMs, so deployments depend on target build tooling and network access.
- The product scope is narrower than `origin/Shabat`: NBU exchange rates only, with no broader market/price/whale dashboard.
- No automated tests.
- No Redis; cache is in-process memory only.
- Local `.env.example` files still contain demo `guest:guest` / `coinops:coinops` values, even though Ansible deployment injects runtime passwords.

### Risks / Technical Debt

- VM/systemd deployment would need substantial rework for AWS container services or Kubernetes.
- No rollback strategy beyond rerunning Ansible.
- No image scanning, dependency checks, or reproducible build artifact.
- No backup/restore runbook for PostgreSQL.
- No observability beyond service logs and health endpoints.
- `ansible/ansible.cfg` disables host key checking, explicitly marked temporary.

### Missing For Production

- Containerization and registry-based deployment.
- Terraform or equivalent IaC for cloud environments.
- CI quality gates and release automation.
- Secrets manager integration.
- TLS, DNS, monitoring, alerting, backups, and migration tooling.
- Kubernetes manifests or Helm/Kustomize packaging.

### Recommended Improvements

- Rank as a useful middle-tier implementation, especially for VM/Ansible quality.
- Borrow its Ansible firewall discipline, five-VM separation, and Go consumer transaction/ack pattern.
- Also borrow its root-owned env-file pattern, Gunicorn/systemd service shape, and graceful shutdown code.
- Do not choose it as the baseline unless the team intentionally ignores Docker, Terraform, AWS, and Kubernetes readiness.
- Add Dockerfiles and a local Compose stack before considering it for cloud migration.
