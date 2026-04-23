# Migration and Demo Runbook

This document provides operational context for the transition to a PostgreSQL-native runtime, deployment guidelines, and emergency fallback procedures.

## 1. Branch Strategy and Code Consolidation

During the migration from the `external` (Redis/RabbitMQ) architecture to the `postgres` runtime, several feature branches were developed concurrently by different team members. 

**Why were these branches not merged directly?**
- **Architectural Shift:** Moving queue, cache, and session management into PostgreSQL fundamentally changed service dependencies.
- **Dependency Chains:** The Go proxy update (`#29`), Python consumer rewrite (`#26`), and cache layer (`#40`) all relied on the foundational Architecture Decision Record (`#33`, ADR 0001).
- **Consolidation:** Feature branches needed to be rebased and consolidated against `dev` to ensure schema migrations (`runtime/00_run_all.sql`) and environment variables (`RUNTIME_BACKEND`) were perfectly synchronized before being exposed to the continuous delivery pipeline.

The `dev` branch serves as the integration environment where these parallel efforts meet, ensuring stability before cutting a SemVer release to `main`.

## 2. Migration Path: External → PostgreSQL

To migrate an existing deployment from the legacy RabbitMQ/Redis architecture to the unified PostgreSQL runtime, follow these steps:

**Prerequisite:** The PostgreSQL instance must be running an image that includes the `pgmq` and `pg_cron` extensions (e.g., `quay.io/tembo/pg16-pgmq` with cron layered on top).

1. **Update Environment Variables:**
   Ensure both the proxy and history consumer `.env` files are updated:
   ```env
   RUNTIME_BACKEND=postgres
   DATABASE_URL=postgresql://cognitor:password@172.31.1.10:5432/cognitor
   ```
2. **Bootstrap the Runtime Schema:**
   Run the PostgreSQL schema initialization script to create the `runtime` schema, functions, and scheduled cron jobs.
   ```bash
   psql "$DATABASE_URL" -f runtime/00_run_all.sql
   ```
3. **Deploy Updated Services:**
   Deploy the latest versions of the proxy and the new python consumer.
   ```bash
   ansible-playbook -i ansible/inventory ansible/deploy.yml
   ```
4. **Verification:**
   - Verify that proxy `/health` is passing.
   - Verify that `runtime.cache` and `runtime.session` are actively receiving writes.
   - Verify that the `pgmq` queues (`market_events`, `price_events`) are actively being consumed by checking queue depths.
5. **Decommissioning:**
   Once verified, RabbitMQ and Redis containers/services can be safely stopped and removed.

## 3. Deployment Commands

The project uses Ansible for deployment. Make sure your inventory is properly configured.

### Continuous Delivery (Demo / Integration)
To deploy the bleeding-edge integration branch (`dev-latest`):

```bash
# Fresh deploy of all services using the latest integration images
IMAGE_TAG=dev-latest ansible-playbook -i ansible/inventory ansible/deploy.yml
```

### Production / Release Deployment
To deploy a specific, immutable SemVer release:

```bash
# Deploy a specific version tag
IMAGE_TAG=v0.2.0 ansible-playbook -i ansible/inventory ansible/deploy.yml
```

### Manual Service Restart
If you need to force a specific container/service to restart and pull the latest image on its respective node:

```bash
docker compose -f deploy/compose/node-02.compose.yaml pull proxy
docker compose -f deploy/compose/node-02.compose.yaml up -d proxy
```

## 4. Rollback Procedures

### Standard Rollback (Previous Version)
If a new SemVer release introduces a regression, you can revert to the previous stable release by re-running the Ansible playbook with the older `IMAGE_TAG`:

```bash
IMAGE_TAG=v0.1.0 ansible-playbook -i ansible/inventory ansible/deploy.yml
```

### Emergency Runtime Fallback
If the PostgreSQL runtime experiences catastrophic failure (e.g., unresolvable extension crashes or queue deadlocks), the system can be temporarily reverted to the legacy RabbitMQ/Redis backend.

1. Re-start the Redis and RabbitMQ services if they were stopped.
2. Edit the environment files for the proxy and history consumer (`/etc/cognitor/proxy.env` and `/etc/cognitor/history.env`) on their respective VMs:
   ```env
   RUNTIME_BACKEND=external
   # Ensure RABBITMQ_URL and REDIS_URL are still present and correct
   ```
3. Restart the proxy and consumer services via Docker Compose:
   ```bash
   ssh vagrant@172.31.1.11 docker compose -f deploy/compose/node-02.compose.yaml restart proxy
   ssh vagrant@172.31.1.10 docker compose -f deploy/compose/node-01.compose.yaml restart history-consumer
   ```
*(Note: Data written to the PostgreSQL queues during the outage will need to be manually drained or reconciled once the backend is restored, as the legacy consumer reads from RabbitMQ only).*
