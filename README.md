# Coin-Ops

Coin-Ops is a distributed Polymarket dashboard deployed across three VMs. The default deployed path on `dev` is still a containerized React + Go + Python system that uses RabbitMQ for asynchronous ingestion and Redis for short-lived UI session state.

At the same time, the roadmap from the April 20-21, 2026 GitHub issues has already started landing on `dev`:

- `dev` is the integration branch for team PRs
- PR validation now runs on pull requests into `dev`
- pushes to `dev` now publish `dev-latest` images
- queue-side PostgreSQL runtime assets are present under `runtime/`
- the full proxy/consumer/deploy cutover behind `RUNTIME_BACKEND=external|postgres` is still pending
- RabbitMQ and Redis are still part of the default deployment until that cutover is verified

**[Read the Documentation](docs/)** | **[How to Contribute](CONTRIBUTING.md)**

## Status Snapshot

| Topic | Current repo state on `dev` | Next planned step |
| --- | --- | --- |
| Runtime backend | Default deployed path is `external`: RabbitMQ queue + Redis session state | Add service/deploy switching so proxy and consumer can run in `postgres` mode |
| Runtime queue assets | `runtime/` already contains `pgmq` queue SQL, DLQ, `LISTEN/NOTIFY`, advisory locks, and `runtime_consumer.py` | Wire proxy and deployment to use those assets |
| Frontend contract | same-origin `/api` and `/history-api` | keep the same HTTP contract while backend internals change |
| Deployment shape | Docker Compose on three VMs via Ansible | keep the three-VM story during the migration |
| Image publishing | `Shabat` -> `shabat-latest`, `dev` -> `dev-latest`, tags -> `vX.Y.Z` | use moving branch tags for integration/demo deploys and tags for pinned releases |
| Validation | PR checks run on pull requests into `dev` | extend the test pyramid beyond the current baseline over time |

## Architecture (PostgreSQL Runtime)

```text
Browser
  |
  v
node-03
  ui container (nginx + React SPA)
  |
  +-- /api -----------> node-02 proxy container :8080
  |                       - fetches Polymarket markets
  |                       - fetches whale leaderboard/positions
  |                       - fetches BTC/ETH and USD/UAH
  |                       - stores session JSON in PostgreSQL (UNLOGGED table)
  |                       - publishes market/price events to PostgreSQL (pgmq/runtime API)
  |
  +-- /history-api ---> node-01 history-api container :8000
                          - reads PostgreSQL history tables

node-01
  postgres container (data + queue + cache + session runtime)
  history-consumer container
    - consumes `market_events` via PostgreSQL runtime API
    - writes `market_snapshots` and `price_snapshots`

node-02
  (Redis is removed or disabled in `postgres` mode)
```

> **Note:** The runtime mode is now PostgreSQL-native (`RUNTIME_BACKEND=postgres`). The legacy mode using RabbitMQ and Redis (`RUNTIME_BACKEND=external`) is kept as a fallback.
> -> See `docs/architecture.md` for details.
> -> See `docs/adr/0001-postgres-runtime.md` for design decisions.

| VM | IP | Runtime services |
| --- | --- | --- |
| node-01 | `172.31.1.10` | PostgreSQL, history consumer, history API |
| node-02 | `172.31.1.11` | Go proxy |
| node-03 | `172.31.1.12` | nginx gateway, React SPA |


## Current Data Flow

| Path | Flow | Purpose |
| --- | --- | --- |
| Live path | Browser -> `/api` -> Go proxy -> external APIs -> Browser | fast live market data |
| Write path | Go proxy -> PostgreSQL (pgmq) -> Python consumer -> PostgreSQL | async persistence |
| History path | Browser -> `/history-api` -> FastAPI -> PostgreSQL -> Browser | chart time series |
| Session path | Browser -> `/api/state` -> PostgreSQL (UNLOGGED) | short-lived UI state |

The browser does not call `172.31.1.10:8000` or `172.31.1.11:8080` directly. Node-03 keeps the frontend same-origin by reverse-proxying `/api` and `/history-api`.

## Roadmap Status

### Already adopted on `dev`

- `dev` is the intended integration branch
- PR checks exist in `.github/workflows/pr-checks.yml`
- GHCR publishing for `dev-latest` exists in `.github/workflows/docker-images.yml`
- PostgreSQL queue-side runtime SQL and `runtime_consumer.py` exist under `runtime/`

### Completed migrations

- added `RUNTIME_BACKEND=external|postgres` wiring to proxy and consumer startup paths
- switched proxy event publishing from RabbitMQ to `runtime.enqueue_event(...)`
- switched deployed consumption from `history/consumer.py` to `runtime/runtime_consumer.py`
- wired runtime schema/bootstrap into Ansible and Compose
- moved Redis-backed session/cache behavior into PostgreSQL runtime primitives
- deprecated RabbitMQ and Redis as primary dependencies

## Tech Stack

| Layer | Tech |
| --- | --- |
| Frontend | React, Vite, TypeScript, Tailwind, Recharts |
| Live gateway | Go |
| History API and current consumer | Python, FastAPI, pgmq (pika for fallback) |
| Queue | PostgreSQL `pgmq` (RabbitMQ for fallback) |
| Database | PostgreSQL |
| Session/runtime state | PostgreSQL `UNLOGGED` tables (Redis for fallback) |
| Containers | Docker, Docker Compose |
| Infrastructure | Terraform for VM provisioning, Ansible for deployment |
| Web server | nginx |

## Repository Layout

```text
.
|-- ansible/          # provisioning and deployment automation
|-- deploy/compose/   # per-node Docker Compose stacks
|-- docs/             # architecture, deployment, and runbook notes
|-- history/          # FastAPI history API, RabbitMQ consumer, schema
|-- proxy/            # Go live-data proxy
|-- runtime/          # PostgreSQL runtime queue SQL and pgmq-backed consumer assets
|-- terraform/        # VM and network provisioning
|-- ui/               # legacy static UI
`-- ui-react/         # main React/Vite frontend
```

## Container Images

Each application service has its own Dockerfile.

| Image | Dockerfile | Runtime shape |
| --- | --- | --- |
| Go proxy | `proxy/Dockerfile` | multi-stage build, `golang:1.22-alpine` builder, `scratch` runtime |
| History API | `history/Dockerfile.api` | `python:3.12-slim-bookworm` |
| History consumer | `history/Dockerfile.consumer` | `python:3.12-slim-bookworm` |
| UI | `ui-react/Dockerfile` | `node:22-bookworm-slim` builder, `nginx:alpine` runtime |

Official images are still used for PostgreSQL, RabbitMQ, and Redis. The queue-side PostgreSQL runtime SQL assumes `pgmq` is available in PostgreSQL, but the default deployment has not been switched over to that path yet.

## Deployment Model

Application images are built by GitHub Actions and pushed to GitHub Container Registry.

```text
push to Shabat
  -> publish shabat-latest

push to dev
  -> publish dev-latest

push tag vX.Y.Z
  -> publish immutable release images

Ansible deploy
  -> renders per-node Compose files and env files
  -> Docker Compose pulls tagged images
  -> containers start on node-01, node-02, and node-03
```

## Branches and Release Tags

Current branch and publishing model:

- `feature/*` -> PR -> `dev`
- `dev` is the integration branch
- `main` remains stable/release-oriented
- `Shabat` publishes moving `shabat-latest`
- `dev` publishes moving `dev-latest`
- `vX.Y.Z` publishes immutable release tags

Release tags are automated from Conventional Commit style squash merge titles on `main`. See [Release Automation](docs/release-automation.md) for the version bump rules and maintainer workflow.

## Public Gateway and TLS

Node-03 is the browser-facing gateway. It serves the React UI and reverse-proxies the backend paths:

```text
https://coinops.test/              -> React UI
https://coinops.test/api/*         -> node-02 proxy
https://coinops.test/history-api/* -> node-01 history API
```

For local lab HTTPS, keep `APP_DOMAIN=coinops.test`, `TLS_MODE=selfsigned`, and add this hosts entry on the machine running the browser:

```text
172.31.1.12 coinops.test
```

## Secrets and Runtime Configuration

Secrets are not baked into images. Ansible writes root-owned env files on the VMs under `/etc/cognitor/`, and Docker Compose injects those values at container startup with `env_file`.

Current runtime env highlights:

- proxy: `RABBITMQ_URL`, `REDIS_URL`, `PORT`
- history: `DATABASE_URL`, `RABBITMQ_URL`, `POSTGRES_*`, `PORT`
- ui: `PROXY_URL=/api`, `HISTORY_URL=/history-api`

Pending full PostgreSQL runtime mode still adds:

- `RUNTIME_BACKEND=external|postgres`
- proxy `DATABASE_URL`
- runtime schema/bootstrap in deployment before app containers start

## Deployment Commands

Prepare environment variables first:

```bash
cp .env.example .env
source .env
```

For the local root `docker compose` flow, use a plain Compose `.env` file and the root `Makefile` convenience targets:

```bash
cp .env.compose.example .env
make local-up
```

Equivalent direct Compose command:

```bash
docker compose up --build
```

This local flow is a developer convenience stack for the default root Compose setup. It does not replace the VM-based Terraform + Ansible deployment flow.

Install pinned Ansible collections:

```bash
ansible-galaxy collection install -r ansible/requirements.yml
```

Provision infrastructure:

```bash
terraform -chdir=terraform apply
```

Install host dependencies and Docker:

```bash
ansible-playbook -i ansible/inventory ansible/provision.yml
```

Deploy application containers:

```bash
ansible-playbook -i ansible/inventory ansible/deploy.yml
```

Current moving-tag deploys:

```bash
IMAGE_TAG=shabat-latest ansible-playbook -i ansible/inventory ansible/deploy.yml
IMAGE_TAG=dev-latest ansible-playbook -i ansible/inventory ansible/deploy.yml
```

Pinned release deploy:

```bash
IMAGE_TAG=v0.1.0 ansible-playbook -i ansible/inventory ansible/deploy.yml
```

## Local Development

Quick local Compose workflow:

```bash
cp .env.compose.example .env
make local-up
```

Open the app at `http://localhost:5000`.

Useful local commands:

```bash
make local-logs
make local-ps
make local-down
make local-restart
make local-config
```

Frontend:

```bash
cd ui-react
npm install
npm run dev
npm run lint
npm run build
```

Go proxy:

```bash
cd proxy
make run
make build
```

Python history services:

```bash
cd history
python -m venv venv
source venv/bin/activate
pip install -r requirements.txt
python main.py
python consumer.py
```

Queue-side PostgreSQL runtime assets:

```bash
psql "$DATABASE_URL" -f runtime/00_run_all.sql
python runtime/runtime_consumer.py
```

Fast Python unit tests for both the current `external` path and the PostgreSQL runtime target:

```bash
cd <repo-root>
python -m venv venv
source venv/bin/activate
pip install -r history/requirements-dev.txt
python -m pytest tests/python/unit
```

If you are already in `history/`, either `cd ..` first or run `python -m pytest ../tests/python/unit`.

The fast `pytest` suite lives under `tests/python/unit`. Keep PostgreSQL-backed integration coverage separate from these unit tests.

PostgreSQL-backed integration tests for `history/main.py` and the queue-side PostgreSQL consumer in `runtime/runtime_consumer.py` (requires Docker):

```bash
cd <repo-root>
python -m venv venv
source venv/bin/activate
pip install -r history/requirements-dev.txt
python -m pytest tests/python/integration -v
```

These integration tests boot an ephemeral runtime-ready PostgreSQL container (`quay.io/tembo/pg16-pgmq@sha256:7f80d046257d585d1af9d19cf28bd355a4b854b0a7d643c02ebbe6b84457868a` by default, override with `COINOPS_TEST_POSTGRES_IMAGE`), apply `history/schema.sql` plus `runtime/00_run_all.sql`, and validate real history read/write behavior through the actual PostgreSQL queue path.

They do not replace the broader runtime smoke tests in `runtime/tests/test_runtime.sql`; cache/session `pg_cron` coverage still lives there.

## External Data Sources

| Source | Data |
| --- | --- |
| `gamma-api.polymarket.com` | live market metadata |
| `data-api.polymarket.com` | whale leaderboard and positions |
| `api.coingecko.com` | BTC and ETH prices |
| `bank.gov.ua` | USD/UAH reference rate |

These are public unauthenticated APIs, so live behavior depends on upstream availability and rate limits.

## More Detail

- [docs/architecture.md](docs/architecture.md) explains the current deployed path versus the PostgreSQL runtime target.
- [docs/runtime-queue-architecture.md](docs/runtime-queue-architecture.md) focuses on the queue-side PostgreSQL runtime design and its current status on `dev`.
