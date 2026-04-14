# Next Sprint Recommendations

## Sprint Goal

Turn `origin/Shabat` into a clean team baseline that can run reproducibly, pass automated checks, and begin a controlled AWS migration without blocking a later Kubernetes move.

2026-04-14 branch refresh impact: `origin/tsyhan`, `origin/kurdupel`, and `origin/volynets` were rechecked from non-Markdown files only. The baseline remains `origin/Shabat`. The next sprint should mine `tsyhan` for Terraform/structlog/settings patterns, `volynets` for VM/systemd/UFW hardening, and `kurdupel` only for a simple Ansible role layout reference.

## Recommended Work Items

### 1. Baseline Cleanup

- Branch from `origin/Shabat`.
- Update stale deployment docs so they match the current GHCR plus Docker Compose deployment.
- Add `ansible/requirements.yml` for required collections such as `community.general`.
- Stop ignoring Terraform provider lock files for real environments.
- Keep `.env.example` as a template only; verify no real secrets are committed.
- Add a short architecture decision record explaining why `Shabat` is the baseline and which ideas are being imported.
- Explicitly compare `Shabat` Ansible against `volynets` Ansible and import useful source-restricted firewall and service-separation patterns.
- Explicitly compare `Shabat` Terraform against `tsyhan` Terraform and split the current Terraform into a cleaner `main.tf` / `variables.tf` / `outputs.tf` shape before starting AWS modules.
- Note that API topic was not part of the selection criteria; queue semantics, persistence, deployment reproducibility, and cloud readiness were.

### 2. Automated Quality Gates

Add GitHub Actions jobs for:

- UI: `npm ci`, `npm run lint`, `npm run build`.
- Go proxy: `go test ./...`, `go build`.
- Python history services: install requirements, import checks, basic unit tests as they are added.
- Docker: build every service image.
- IaC: `terraform fmt -check`, `terraform validate`.
- Ansible: `ansible-lint` once playbooks are normalized.
- Security: image vulnerability scan and dependency audit.

Acceptance target: every PR has deterministic pass/fail checks before merge.

### 3. Reproducible Local Development

- Add a root-level `compose.local.yml` for the full stack on one developer machine.
- Use `.env.example` for local ports, DB credentials, RabbitMQ credentials, Redis URL, and service URLs.
- Add a `Makefile` or `scripts/dev.ps1`/`scripts/dev.sh` wrapper for common commands.
- Add a smoke test script that checks UI, proxy `/health`, history API `/health`, RabbitMQ, Postgres, and Redis.

Acceptance target: a new developer can run the system locally without creating VMs.

### 4. Secrets and Configuration

- Validate required environment variables at service startup.
- Move demo VM secrets to Ansible Vault or generated local `.env` only.
- For AWS, use Secrets Manager or SSM Parameter Store.
- Remove hardcoded service IPs from application defaults where possible.
- Document config names once and reuse them across Compose, Ansible, and future Kubernetes.
- Keep `volynets` as the reference branch for cleaner VM-only Ansible boundaries while moving the chosen baseline toward image-based deploys.
- Keep `tsyhan` as the reference branch for Terraform/cloud-init layout and `structlog`/Pydantic settings.
- Keep `kurdupel` out of the baseline path until it has portable inventory, Docker images, and ACK-after-confirmed-write behavior.

Acceptance target: deployment fails fast on missing config and never requires editing source code for environment changes.

### 5. AWS Terraform MVP

Create `infra/aws/` or `terraform/aws/` separate from the Hyper-V demo.

Minimum resources:

- S3 backend and DynamoDB lock table for Terraform state.
- VPC, public/private subnets, route tables, NAT path if private workloads need internet.
- Security groups with least-privilege inbound rules.
- ECR repositories for app images.
- RDS PostgreSQL with backups enabled.
- ElastiCache Redis or documented reason for deferring it.
- Queue option: Amazon MQ for RabbitMQ compatibility, or RabbitMQ on EC2 for a short interim step.
- EC2 or ECS/Fargate runtime for the app containers.
- ALB plus ACM TLS.

Acceptance target: Terraform can create an AWS staging environment from scratch.

### 6. Deployment and Release Process

- Build images once per commit.
- Tag images by commit SHA and optionally environment aliases.
- Deploy by image tag, not by pulling source onto servers.
- Add rollback instructions: previous image tag, database migration constraints, and verification commands.
- Add deployment health gates before marking a release successful.

Acceptance target: the team can deploy and roll back a known image tag.

### 7. Data Reliability

- Add migration tooling for PostgreSQL schema changes.
- Add scheduled database backups and a restore drill.
- Keep ack-after-commit behavior for consumers.
- Add dead-letter or poison-message handling for malformed queue messages.
- Define message schemas and versioning rules.

Acceptance target: message processing and database changes have a documented failure model.

### 8. Observability

- Standardize structured JSON logs or at least consistent log fields.
- Add metrics endpoints or sidecar/exporter plan.
- Add CloudWatch alarms for service health, queue depth, consumer errors, RDS storage/CPU, and ALB 5xx.
- Write a runbook for common incidents: upstream API outage, RabbitMQ backlog, DB connection exhaustion, failed deploy.

Acceptance target: an operator can identify whether the UI, proxy, queue, consumer, or DB is the failing layer.

### 9. Kubernetes Readiness

- Add Dockerfile `HEALTHCHECK` or explicit app health endpoints for every custom service.
- Add graceful shutdown handling for proxy/API/consumer.
- Define resource needs for each service.
- Draft Helm or Kustomize manifests after the AWS container path is stable.
- Keep PostgreSQL/Redis/RabbitMQ external unless the team explicitly chooses to operate them in-cluster.

Acceptance target: app containers are ready to be mapped to Kubernetes Deployments without changing application code.

## Suggested Sprint Order

1. Baseline cleanup and docs.
2. CI quality gates.
3. Local full-stack Compose.
4. Secrets/config normalization.
5. AWS Terraform skeleton with remote state.
6. First AWS staging deploy.
7. Observability and backup runbooks.
8. Kubernetes manifest draft.

## Non-Goals For The Next Sprint

- Full production Kubernetes cluster.
- Multi-region high availability.
- Complex service mesh.
- Rewriting the application domain.
- Adopting every idea from every branch.

The next sprint should make one baseline solid, reproducible, and cloud-migratable.
