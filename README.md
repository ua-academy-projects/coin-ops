# Coin-Ops

Coin-Ops is a distributed Polymarket intelligence dashboard. It shows live markets, BTC/ETH prices, USD/UAH, whale-style position data, and historical probability charts across a small three-VM deployment.

The project is intentionally not a single web app. It separates live aggregation, async ingestion, historical storage, and UI delivery so the architecture is easy to reason about and easy to demonstrate.

## Architecture

```text
                                   Browser
                              React/Vite SPA
                                      |
                    +-----------------+-----------------+
                    |                                   |
                    | live data                         | history charts
                    v                                   v
        +-------------------------+        +-------------------------+
        | node-02                 |        | node-01                 |
        | Go proxy :8080          |        | FastAPI history :8000   |
        |                         |        |                         |
        | - Polymarket markets    |        | - Reads PostgreSQL      |
        | - Whale positions       |        | - Returns time series   |
        | - BTC/ETH from CoinGecko|        +------------+------------+
        | - USD/UAH from NBU      |                     |
        | - UI state via Redis    |                     | SELECT
        | - Publishes to RabbitMQ |                     v
        +------------+------------+        +-------------------------+
                     |                     | PostgreSQL              |
                     | AMQP publish        | market/price snapshots  |
                     v                     | whale snapshots         |
        +-------------------------+        +-------------------------+
        | node-01                 |
        | Python history consumer |
        |                         |
        | - Consumes RabbitMQ     |        +-------------------------+
        | - Writes PostgreSQL     |        | node-02                 |
        | - Idempotent inserts    |        | Redis                   |
        +-------------------------+        | short-lived UI state    |
                                           +-------------------------+
```

| VM | IP | Runs |
| --- | --- | --- |
| node-01 | `172.31.1.10` | PostgreSQL, RabbitMQ, history consumer, history API |
| node-02 | `172.31.1.11` | Go proxy, Redis |
| node-03 | `172.31.1.12` | nginx, React SPA |

## Data Flow

| Path | Flow | Purpose |
| --- | --- | --- |
| Live path | Browser -> Go proxy -> external APIs -> Browser | Fast current market data |
| Write path | Go proxy -> RabbitMQ -> Python consumer -> PostgreSQL | Async persistence |
| History path | Browser -> FastAPI -> PostgreSQL -> Browser | Chart time series |

The proxy does not write directly to PostgreSQL. It publishes events into RabbitMQ, and the consumer owns database writes. That keeps the live request path independent from database latency.

## Tech Stack

| Layer | Tech |
| --- | --- |
| Frontend | React, Vite, TypeScript, Tailwind, Recharts |
| Live gateway | Go |
| History API and consumer | Python, FastAPI, pika |
| Queue | RabbitMQ |
| Database | PostgreSQL |
| Cache | Redis |
| Containers | Docker, Docker Compose |
| Infrastructure | Terraform for Hyper-V VMs, Ansible for provisioning/deploy |
| Web server | nginx inside the UI container |

## Repository Layout

```text
.
|-- ansible/          # provisioning and deployment automation
|-- deploy/compose/   # per-node Docker Compose stacks
|-- history/          # FastAPI history API, RabbitMQ consumer, schema
|-- proxy/            # Go live-data proxy
|-- terraform/        # Hyper-V VM and network provisioning
|-- ui/               # legacy static UI
`-- ui-react/         # main React/Vite frontend
```

## Container Images

Each application service has its own Dockerfile.

| Image | Dockerfile | Runtime shape |
| --- | --- | --- |
| Go proxy | `proxy/Dockerfile` | multi-stage build, `golang:1.22-alpine` builder, `scratch` runtime |
| History API | `history/Dockerfile.api` | `python:3.12-slim-bookworm`, non-root user |
| History consumer | `history/Dockerfile.consumer` | `python:3.12-slim-bookworm`, non-root user |
| UI | `ui-react/Dockerfile` | `node:22-bookworm-slim` builder, `nginx:alpine` runtime |

Official images are used for PostgreSQL, RabbitMQ, and Redis.

## Current Deployment Model

The current deployment builds images on the target VMs:

```text
developer machine / WSL
  -> ansible-playbook deploy.yml
  -> Ansible SSHs into each VM
  -> source is synced to /opt/cognitor/<service>/
  -> env files are written to /etc/cognitor/*.env
  -> Compose files are copied/rendered
  -> docker compose up -d --build starts containers
```

This is simple and works well for a local three-VM Hyper-V demo. The tradeoff is that VMs need source code during deployment because Docker builds the images there.

The more production-like next step is registry-based deployment:

```text
GitHub Actions
  -> docker build
  -> docker push ghcr.io/<owner>/coin-ops-<service>:<commit-sha>
  -> Ansible writes env files
  -> Ansible runs docker compose pull && docker compose up -d
```

That would remove source code from the runtime VMs and make deployments use immutable image artifacts.

## Secrets and Runtime Configuration

Secrets are not baked into Docker images. Ansible writes root-owned env files on the VMs under `/etc/cognitor/`, and Docker Compose injects those values at container startup with `env_file`.

This keeps images environment-agnostic and safe to publish. For this project scale, host env files are a reasonable tradeoff. In a larger production system, this would usually move to Vault, a cloud secrets manager, Docker Swarm secrets, or Kubernetes secrets.

## Deployment

Prepare environment variables first:

```bash
cp .env.example .env
source .env
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

Deploy only one node:

```bash
ansible-playbook -i ansible/inventory ansible/deploy.yml --limit softserve-node-02
```

## Local Development

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

## External Data Sources

| Source | Data |
| --- | --- |
| `gamma-api.polymarket.com` | live market metadata |
| `data-api.polymarket.com` | whale leaderboard and positions |
| `api.coingecko.com` | BTC and ETH prices |
| `bank.gov.ua` | USD/UAH reference rate |

These are public unauthenticated APIs, so live behavior depends on upstream availability and rate limits.

## Operational Notes

The deployment is safe to re-run. Ansible stops legacy host services, renders current Compose files, starts containers, waits for health endpoints, and removes unused Docker build cache after successful rollout.

Persistent data is stored on VM-mounted host paths under `/var/lib/coin-ops/`, not inside disposable container layers.
