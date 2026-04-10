# Coin-Ops

A distributed Polymarket intelligence dashboard. Live market data, crypto prices, whale positions, and historical charts — built across three services and three VMs with full infrastructure automation.

---

## Architecture

```
                        ┌─────────────────────────────────┐
                        │         Browser (React SPA)      │
                        └──────┬───────────────┬───────────┘
                               │ live data      │ history
                               ▼                ▼
┌──────────────────────────────────┐   ┌────────────────────────────┐
│  node-02  ·  Go Proxy  :8080     │   │  node-01  ·  History API    │
│                                  │   │            FastAPI  :8000   │
│  • Fetches Polymarket markets    │   │                            │
│  • Fetches CoinGecko + NBU       │   │  Reads from PostgreSQL     │
│  • Caches whales (5 min)         │   └───────────┬────────────────┘
│  • Caches prices (60 s)          │               │
│  • Session state → Redis         │               │ SELECT
│  • Publishes events → RabbitMQ   │               ▼
└──────┬───────────────────────────┘   ┌────────────────────────────┐
       │                               │  PostgreSQL                │
       │ AMQP publish                  │  market_snapshots          │
       ▼                               │  price_snapshots           │
┌──────────────────────────────────┐   │  whales / positions        │
│  node-01  ·  History Consumer    │   └────────────────────────────┘
│                                  │
│  Consumes market_events queue    │
│  Routes by type field            │
│  Inserts with ON CONFLICT        │   ┌────────────────────────────┐
│  DO NOTHING (idempotent)         │   │  node-02  ·  Redis         │
└──────────────────────────────────┘   │  Session state only        │
                                       │  Non-critical — 503 if down│
                                       └────────────────────────────┘
```

| VM | IP | Runs |
|----|-----|------|
| node-01 | 172.31.1.10 | PostgreSQL · RabbitMQ · history consumer · history API |
| node-02 | 172.31.1.11 | Go proxy · Redis |
| node-03 | 172.31.1.12 | nginx · React SPA |

---

## Data Flow

**Live path** — Browser → Go proxy → external APIs → JSON response  
**Write path** — Go proxy → RabbitMQ → Python consumer → PostgreSQL  
**History path** — Browser → FastAPI → PostgreSQL → chart data

The write path is intentionally async. The proxy never blocks on a DB write; RabbitMQ absorbs backpressure.

---

## Tech Stack

| Layer | Tech |
|-------|------|
| Frontend | React 19, Vite, TypeScript, Tailwind, Recharts |
| Live gateway | Go 1.22 |
| History service | Python 3.12, FastAPI, pika |
| Queue | RabbitMQ |
| Database | PostgreSQL 16 |
| Cache | Redis 7 |
| Containers | Docker, Docker Compose (per-node) |
| Provisioning | Terraform (`taliesins/hyperv`), Ansible |
| Web server | nginx (inside container) |

---

## Containers

Each service has its own Dockerfile. Deployment uses one Compose file per VM, managed by Ansible.

### Images

**`proxy/Dockerfile`** — two-stage build: `golang:1.22-bookworm` compiles the binary, then it's copied into `distroless/static` — no shell, no OS packages, non-root.

**`history/Dockerfile.api`** and **`history/Dockerfile.consumer`** — `python:3.12-slim-bookworm`, deps installed before source copy so the layer is cached. Both run as a dedicated non-root `user`.

**`ui-react/Dockerfile`** — two-stage: `node:22` builds the Vite bundle, output is copied into `nginx:alpine`. The nginx config is baked into the image.

### Compose layout

```
deploy/compose/
  node-01.compose.yaml   # postgres + rabbitmq + history-consumer + history-api
  node-02.compose.yaml   # redis + proxy
  node-03.compose.yaml   # ui (nginx + SPA)
```

Each Compose file reads secrets from `/etc/cognitor/*.env` on the host — written by Ansible at deploy time, never in the image. Services declare `healthcheck` + `depends_on: condition: service_healthy` so startup order is enforced.

### Build and run

```bash
# Proxy
docker build -t coin-ops/proxy ./proxy

# History API / Consumer
docker build -t coin-ops/history-api -f history/Dockerfile.api ./history
docker build -t coin-ops/history-consumer -f history/Dockerfile.consumer ./history

# UI
docker build -t coin-ops/ui ./ui-react

# Start a node (run on the target VM)
docker compose -f deploy/compose/node-01.compose.yaml up -d
```

---

## Deployment

Prerequisites: `source .env` before any Terraform or Ansible command.

```bash
# 1. Provision VMs (one-time)
terraform -chdir=terraform apply

# 2. Install OS deps + Docker on all nodes
ansible-playbook -i ansible/inventory ansible/provision.yml

# 3. Build images and start all services
ansible-playbook -i ansible/inventory ansible/deploy.yml

# 4. Redeploy a single node
ansible-playbook -i ansible/inventory ansible/deploy.yml --limit softserve-node-02,localhost
```

Ansible builds Docker images on each target VM, writes env files to `/etc/cognitor/`, deploys the Compose file, and runs `docker compose up -d --build`.

---

## Local Development

### Frontend
```bash
cd ui-react
npm install
npm run dev       # :3000
npm run lint      # tsc --noEmit
npm run build
```

### Go proxy
```bash
cd proxy
make run          # go run .
make build        # cross-compile → proxy-linux
```

### Python history
```bash
cd history
python -m venv venv && source venv/bin/activate
pip install -r requirements.txt
python consumer.py   # needs RabbitMQ + Postgres
python main.py       # needs Postgres
```

---

## External Data Sources

| Source | Data |
|--------|------|
| `gamma-api.polymarket.com` | Live markets |
| `data-api.polymarket.com` | Whale leaderboard + positions |
| `api.coingecko.com` | BTC / ETH prices |
| `bank.gov.ua` | USD / UAH rate |

All public, no auth required.

---

## Environment

Copy `.env.example` to `.env` and fill in values. Required before any Terraform or Ansible run:

```bash
cp .env.example .env
source .env
```

Key variables: `SSH_KEY_PATH`, `TF_VAR_winrm_*`, `TF_VAR_*_path`, `RABBITMQ_PASSWORD`, `DB_PASSWORD`.
