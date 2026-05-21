# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Architecture

Three application services run across three GCP VMs:

| Role | Service set |
|------|-------------|
| history VM | History consumer + FastAPI + (PostgreSQL/RabbitMQ on local backend, Cloud SQL on GCP) |
| proxy VM   | Go proxy + Redis |
| ui VM      | React SPA + nginx |

A separate 3-node k3s lab runs in parallel for Kubernetes work.

**Data flow:** Browser → nginx (ui VM) → Go proxy (proxy VM) → Polymarket/CoinGecko/NBU APIs → publishes to RabbitMQ → Python consumer (history VM) inserts into PostgreSQL → History API (history VM) serves historical data back to browser.

**Proxy** (`services/proxy/main.go`) — stateless Go service. Fetches 20 live Polymarket markets, whale leaderboard, and BTC/ETH/UAH prices. Caches whales (5 min) and prices (60s). Publishes market and price events to RabbitMQ. Stores session state in Redis (non-critical; 503 if Redis unavailable).

**History** (`services/history/`) — two Python processes sharing the same codebase:
- `consumer.py` — pika RabbitMQ consumer, routes by `type` field: market events → `market_snapshots`, price events → `price_snapshots`. Idempotent writes via `ON CONFLICT DO NOTHING`.
- `main.py` — FastAPI server on port 8000 with endpoints: `/history`, `/history/{slug}`, `/prices/history/{coin}`, `/health`.

**UI** (`services/ui/`) — React + Vite + Recharts SPA. Service URLs come from Vite env vars (`VITE_PROXY_URL`, `VITE_HISTORY_URL`).

**Runtime** (`services/runtime/`) — PostgreSQL-backed runtime queue (pgmq + LISTEN/NOTIFY + DLQ + pg_cron). Replaces RabbitMQ + Redis when `RUNTIME_BACKEND=postgres`.

## Repository Layout

```text
services/        # application source code (history, proxy, runtime, ui, postgres-runtime)
deployments/     # how the app runs per environment (local, smoke, gcp-vm, k3s)
ansible/         # configuration + deployment automation
  inventories/   # gcp-vm, gcp-k3s
  playbooks/     # vm-provision.yml, vm-deploy.yml, k3s-cluster.yml
  roles/
tests/           # unit + integration pytest suites
docs/            # architecture, infrastructure, deployment, operations
deprecated/      # frozen Hyper-V lab
```

## Commands

### Proxy (Go)
```bash
cd services/proxy
make build    # cross-compile → proxy-linux (GOOS=linux GOARCH=amd64)
make run      # local run
make tidy     # go mod tidy
go test ./... # fast unit tests
```

### UI (React)
```bash
cd services/ui
npm run dev      # dev server on :3000
npm run build    # production build → dist/
npm run lint     # tsc --noEmit
```

### History (Python)
No local runner — deploy via Ansible or run manually: `python3 main.py` / `python3 consumer.py`.

### Local stack
```bash
cp deployments/local/.env.example deployments/local/.env
make local-up
make smoke              # full smoke suite
make smoke-postgres     # postgres-runtime variant
```

## Deployment

```bash
# GCP VM provisioning lives in the gcp-terraform-bootstrap repo.
# OS setup (Docker, kernel params, UFW)
ansible-playbook -i ansible/inventories/gcp-vm ansible/playbooks/vm-provision.yml

# Deploy / update all services
ansible-playbook -i ansible/inventories/gcp-vm ansible/playbooks/vm-deploy.yml

# Image tag pinning
IMAGE_TAG=v0.1.0 ansible-playbook -i ansible/inventories/gcp-vm ansible/playbooks/vm-deploy.yml
```

Per-role compose files live in `deployments/gcp-vm/` (`history.compose.yaml`, `proxy.compose.yaml`, `ui.compose.yaml`). Ansible roles render those templates onto the VMs.

## k3s Cluster Lab

```bash
ansible-playbook -i ansible/inventories/gcp-k3s ansible/playbooks/k3s-cluster.yml
kubectl get nodes -o wide
kubectl -n kube-system port-forward service/headlamp 8080:80
```

See `docs/infrastructure/k3s-cluster.md`.

## Infrastructure Details

- **Terraform** for GCP VMs lives in the separate `gcp-terraform-bootstrap` repo.
- **Secrets** are read from GCP Secret Manager at deploy time and are not written to disk.
- The old Hyper-V Terraform setup is frozen under `deprecated/hyperv-lab/` and not used on `dev`.

## Database Schema

Tables in PostgreSQL on history VM (`services/history/schema.sql`):
- `market_snapshots` — one row per market per `/current` call; UNIQUE(slug, fetched_at)
- `price_snapshots` — BTC/ETH/USD_UAH prices; UNIQUE(coin, fetched_at)
- `whales`, `whale_positions` — leaderboard + open positions

Runtime queue/cache schema lives in `services/runtime/sql/`.
