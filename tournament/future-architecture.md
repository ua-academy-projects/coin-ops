# Unified Future Architecture Proposal

## Baseline Direction

Start from `origin/Shabat` and evolve it in two stages:

1. AWS-ready container deployment that still resembles the current VM topology.
2. Kubernetes-ready platform shape with stateless services separated from managed state.

The goal is not to preserve every VM detail forever. The goal is to preserve the strongest service boundaries while moving state and deployment concerns into managed or orchestrated infrastructure.

2026-04-14 update: the refreshed `origin/tsyhan`, `origin/kurdupel`, and `origin/volynets` branches do not change the baseline decision. They do change the import list: `tsyhan` is now the strongest Terraform/observability reference, `volynets` is the strongest VM/systemd hardening reference, and `kurdupel` is a useful simple Ansible-role reference only.

## Target Service Model

```text
Browser
  -> UI: React static assets served by nginx now, CDN/S3/CloudFront later
  -> Go live proxy: stateless HTTP service
  -> FastAPI history API: stateless read API
  -> History consumer workers: horizontally scalable queue consumers

Go proxy
  -> External APIs: Polymarket, CoinGecko, NBU
  -> Redis: short-lived UI/session/cache state
  -> RabbitMQ or managed queue: event persistence boundary

Consumers
  -> PostgreSQL: historical market/price/whale data

History API
  -> PostgreSQL: read-only time-series queries
```

## AWS Phase

Recommended AWS landing shape for the next sprint:

- Terraform remote state in S3 with DynamoDB locking.
- VPC with public and private subnets across at least two Availability Zones.
- ECR for application images, even if GHCR remains supported for demos.
- RDS PostgreSQL for history data.
- ElastiCache Redis for session/cache state.
- Amazon MQ for RabbitMQ compatibility, or a deliberate decision to migrate to SQS/SNS if the app can accept that semantic change.
- ECS/Fargate or EC2 with Docker Compose as the first cloud runtime.
- Application Load Balancer with ACM TLS certificate.
- CloudWatch logs and alarms.
- Secrets Manager or SSM Parameter Store for database, queue, Redis, and registry credentials.

Pragmatic path: start with EC2 plus Docker Compose if the team needs a small migration step from VMs. Prefer ECS/Fargate if the team can absorb the extra AWS concepts now. Both paths should use the same images and environment contract.

## Kubernetes Phase

Prepare for Kubernetes without rushing into it:

- Define one container image per service.
- Add `/health` or equivalent liveness/readiness endpoints to every custom service.
- Externalize all config through environment variables.
- Keep state outside application pods: RDS, managed Redis, managed queue, or explicitly managed StatefulSets only if required.
- Add resource requests/limits and graceful shutdown behavior.
- Package workloads with Helm or Kustomize.

Kubernetes object mapping:

| Current component | Kubernetes shape |
| --- | --- |
| UI container | `Deployment` + `Service` + `Ingress` or CDN outside cluster |
| Go proxy | `Deployment` + `Service` + HPA |
| History API | `Deployment` + `Service` + HPA |
| History consumer | `Deployment` scaled by queue depth |
| PostgreSQL | Prefer RDS outside cluster |
| Redis | Prefer ElastiCache outside cluster |
| RabbitMQ | Prefer Amazon MQ or managed RabbitMQ; otherwise operator-managed StatefulSet |
| Runtime config | `ConfigMap` plus external secrets integration |
| Secrets | External Secrets Operator backed by AWS Secrets Manager/SSM |

## Ideas To Merge From Branches

### From `origin/Shabat`

- Keep the core application and service boundaries.
- Keep image-based deployment and environment templating.
- Keep per-service Dockerfiles and Compose health dependency patterns.
- Keep Ansible roles as the VM/EC2 bridge until cloud-native deployment replaces them.

### From `origin/hrenchevskyi`

- Add stricter app config validation.
- Add security headers and rate limiting where applicable.
- Improve runbooks with smoke tests and operational commands.
- Consider Ansible Vault only for local VM demos; cloud should use AWS secrets.

### From `origin/kazachuk`

- Add a single local developer Compose stack for the full system.
- Reuse the idea of named volumes and health-gated dependencies.
- Fix queue durability using the stronger ack-after-commit pattern from `Shabat`.

### From `origin/tsyhan`

- Reuse the clearer Terraform variable/output description style.
- Reuse cloud-init templating ideas if EC2 cloud-init remains part of the path.
- Reuse the Pydantic settings and `structlog` patterns.
- Reuse separate Redis/RabbitMQ VM modeling as a temporary VM bridge, but prefer managed Redis/queue on AWS.
- Do not reuse cron-based Git polling deploys.
- Do not reuse the worker-writes-directly-to-Postgres ingestion path as the primary queue model.

### From `origin/volynets`

- Reuse the clean five-VM Ansible separation as a reference for service ownership: UI, proxy, queue, history service, and database.
- Reuse the source-restricted UFW approach for VM or EC2 security-group thinking.
- Reuse the Go history consumer pattern: transaction per batch, manual ack after commit, nack/requeue on transient failure, and idempotent upsert.
- Reuse root-owned env files for VM deployments, Gunicorn/systemd service shape for Python web processes, and graceful shutdown handling from the Go services.
- Do not reuse target-VM builds as the long-term delivery model; convert these services to images before AWS/Kubernetes migration.

### From `origin/kurdupel`

- Reuse only the simple role-per-service Ansible layout as a teaching/reference pattern.
- Do not reuse `/vagrant` runtime coupling, absolute private-key inventory paths, Redis protected-mode disablement, or ACK-after-logged-error consumer behavior.

### From `origin/zakipnyi`

- Keep the five-role topology as a conceptual scaling model:
  UI, proxy, history API/consumer, queue, database.
- Do not keep shell-only provisioning as the long-term mechanism.

## Production Architecture Principles

- Stateless application containers; managed or explicitly backed-up state.
- Immutable image tags and controlled promotion.
- No secrets in Git, Dockerfiles, Compose files, or Terraform variables committed with real values.
- Cloud network boundaries instead of host-only IP assumptions.
- Health checks at container, load balancer, and deployment levels.
- Observability from day one: structured logs, metrics, alerts, dashboards.
- Database migrations as explicit release steps.
- Backup and restore tested before declaring production readiness.
