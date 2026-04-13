# Branch-by-Branch Comparison

This file covers all 11 inspected branches, including `main` and `volynets`.

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
- Some documentation still describes the older systemd/source-sync deployment path while the current README and playbooks use GHCR plus Docker Compose.
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
- Update or clearly label stale systemd-era docs.
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
- README explains blockers and operational commands clearly.

### Weaknesses

- Hardcoded credentials appear in Compose, Ansible, source defaults, and documentation.
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

## `origin/monero-privacy-system`

### Summary

Separate Monero privacy analytics product. It has a React frontend, FastAPI backend, worker, PostgreSQL, local Docker Compose, deploy scripts, Alpine/OpenRC production VM model, and libvirt Terraform with cloud-init.

### Strengths

- Strongest standalone Terraform/cloud-init experiment outside `Shabat`.
- Terraform models network, static IPs, VM disks, cloud-init disks, variables, and outputs.
- Cloud-init files install packages, create users, write config, define OpenRC services, and bootstrap deploy scripts.
- Docker backend runs as non-root and includes a health check.
- Documentation covers local dev, VM production deployment, RPC dependencies, and verification commands.

### Weaknesses

- It is a different application/domain and does not implement the Coin-Ops Polymarket or currency dashboard architecture.
- No RabbitMQ/event-ingestion shape comparable to the current project baseline.
- Production deploy model uses cron polling from Git every minute, which is not a controlled release mechanism.
- Terraform is libvirt/KVM specific, not AWS.
- No CI, no image registry deployment, no Kubernetes manifests.

### Risks / Technical Debt

- Product mismatch makes it risky as a team baseline even though some IaC ideas are useful.
- Auto-deploy from branch state can deploy unreviewed or broken commits.
- Terraform state would contain secrets rendered into cloud-init.
- Small VM sizes and Alpine/OpenRC assumptions may not represent the team target.

### Missing For Production

- Coin-Ops application functionality.
- Controlled release pipeline, rollback, monitoring, TLS, backups, and cloud-managed dependencies.
- AWS modules and Kubernetes packaging.

### Recommended Improvements

- Do not use as the baseline.
- Reuse the clearer cloud-init structure, Terraform outputs, and static network modeling ideas when building AWS/VM modules.
- Replace cron-pull deployment with CI/CD-controlled image promotion.

## `origin/penina`

### Summary

Five-VM currency dashboard design with Flask/React UI, Python proxy, RabbitMQ, Go history service, PostgreSQL, Redis, Ansible playbooks, and a Docker Compose attempt.

### Strengths

- Clear five-VM architecture and data flow in the README.
- Documents real operational blockers and learning around Docker, RabbitMQ definitions, Redis caching, and image size.
- Includes separate service directories and a RabbitMQ definitions file.
- Attempts both systemd VM deployment and Docker Compose.

### Weaknesses

- Docker Compose build paths do not match committed directories (`./proxy`, `./history`, `./ui` under `docker/` are not present).
- Ansible playbooks reference missing `ansible/files/...` sources.
- Credentials and IPs are hardcoded in playbooks, Compose, source, and docs.
- No Terraform, no CI, and no registry.
- Systemd, Docker, and documentation drift apart.

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
- Consolidate docs to match runnable commands.
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
- Credentials and fixed IPs are hardcoded throughout Vagrant, source defaults, and docs.
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

Partial four-VM Vagrant scaffold with Flask UI, Flask proxy, Go history service, RabbitMQ/PostgreSQL interaction, and a single Ansible playbook for PostgreSQL.

### Strengths

- Basic service separation exists: UI, proxy, history, data.
- Some RabbitMQ usage is durable and messages are persistent.
- Services read several connection values from environment variables.

### Weaknesses

- No complete VM provisioning for UI, proxy, RabbitMQ, or history service.
- No Docker, Terraform, CI, or registry.
- No README/runbook.
- Debug mode is enabled in Flask services.
- Hardcoded weak defaults and local assumptions remain.

### Risks / Technical Debt

- Not reproducible as a full environment from the committed automation.
- Error handling is fragile, including unsafe type assertions in Go history code.
- Manual service startup and configuration would be required.

### Missing For Production

- Nearly all production foundations: full provisioning, secrets, tests, Docker, cloud IaC, TLS, backups, monitoring, and Kubernetes packaging.

### Recommended Improvements

- Treat as an early prototype.
- Add complete Ansible roles or replace with the stronger baseline.

## `origin/shturyn`

### Summary

Small React/Vite frontend and Go weather proxy. It is not a Coin-Ops currency/Polymarket implementation and contains no meaningful infrastructure automation.

### Strengths

- Minimal frontend/backend split exists.
- Frontend has Vite/TypeScript project scaffolding.

### Weaknesses

- Wrong product domain: weather instead of Coin-Ops.
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

Same state as `origin/main`: MIT license only.

### Strengths

- Clean, no generated artifacts.

### Weaknesses

- No implementation.

### Risks / Technical Debt

- No baseline value for the next sprint.

### Missing For Production

- Everything beyond the license.

### Recommended Improvements

- Do not rank as an implementation candidate.
