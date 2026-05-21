# Coin-Ops

Coin-Ops is a distributed Polymarket dashboard. The default deployed path on
`dev` is a containerized React + Go + Python stack that uses RabbitMQ for
asynchronous ingestion and Redis for short-lived UI session state, running
on three GCP VMs driven by Ansible. A separate k3s learning cluster lives in
parallel for Kubernetes work.

**[Read the Documentation](docs/)** | **[How to Contribute](CONTRIBUTING.md)**

## Repository Layout

```text
.
├── services/                 # application source code
│   ├── history/              # FastAPI history API + RabbitMQ consumer + schema
│   ├── proxy/                # Go live-data proxy
│   ├── runtime/              # PostgreSQL runtime queue
│   │   ├── sql/              #   pgmq / LISTEN-NOTIFY / DLQ / cache SQL
│   │   ├── src/              #   runtime_consumer.py
│   │   └── tests/            #   test_runtime.sql
│   ├── ui/                   # React + Vite frontend
│   └── postgres-runtime/     # custom Postgres image (pgmq + pg_cron)
│
├── deployments/              # how the app runs in each target environment
│   ├── local/                # docker compose for local dev on the Mac
│   ├── smoke/                # docker compose + smoke.sh for end-to-end checks
│   ├── gcp-vm/               # per-role compose files for the 3-VM GCP stack
│   └── k3s/                  # placeholder for Kubernetes manifests / Helm
│
├── ansible/                  # configuration + deployment automation
│   ├── inventories/
│   │   ├── gcp-vm/           # 3-node VM inventory + group_vars
│   │   └── gcp-k3s/          # k3s lab inventory + group_vars
│   ├── playbooks/
│   │   ├── vm-provision.yml  # OS / Docker setup on VMs
│   │   ├── vm-deploy.yml     # render compose, pull images, run stack
│   │   └── k3s-cluster.yml   # bring up HA k3s on the lab VMs
│   ├── roles/
│   │   ├── common, docker            # shared
│   │   ├── history, proxy, ui        # VM app roles
│   │   └── haproxy_k3s_api,
│   │       k3s_node_prep, k3s_server # k3s roles
│   └── requirements.yml
│
├── tests/
│   ├── unit/                 # fast pytest unit tests (no Docker)
│   └── integration/          # PostgreSQL-backed pytest integration tests
│
├── docs/                     # architecture, infrastructure, deployment, ops
│   ├── architecture/
│   ├── infrastructure/
│   ├── deployment/
│   └── operations/
│
├── deprecated/               # frozen snapshots not used on dev
│   └── hyperv-lab/           # old Hyper-V terraform + inventory
│
├── .github/workflows/        # CI: build images, PR checks, release-please
├── Makefile                  # local-up / local-down / smoke entrypoints
└── README.md / CLAUDE.md / AGENTS.md / CONTRIBUTING.md
```

## Current Architecture (`external` runtime path)

```text
Browser
  |
  v
ui VM
  ui container (nginx + React SPA)
  |
  +-- /api -----------> proxy VM, proxy container :8080
  |                       - fetches Polymarket markets
  |                       - fetches whale leaderboard/positions
  |                       - fetches BTC/ETH and USD/UAH
  |                       - stores session JSON in Redis
  |                       - publishes market/price events to RabbitMQ
  |
  +-- /history-api ---> history VM, history-api container :8000
                          - reads PostgreSQL history tables

history VM
  postgres container
  rabbitmq container
  history-consumer container
    - consumes `market_events`
    - writes `market_snapshots` and `price_snapshots`

proxy VM
  redis container

ui VM
  nginx gateway
```

## Tech Stack

| Layer | Tech |
| --- | --- |
| Frontend | React, Vite, TypeScript, Tailwind, Recharts |
| Live gateway | Go |
| History API and current consumer | Python, FastAPI, pika |
| Queue | RabbitMQ for the default path; pgmq queue assets under `services/runtime/` |
| Database | PostgreSQL (Cloud SQL on GCP) |
| Session/runtime state | Redis today; PostgreSQL runtime consolidation planned |
| Containers | Docker, Docker Compose |
| Infrastructure | Terraform (external repo for GCP), Ansible for deployment |
| Web server | nginx |

## Local Development

```bash
cp deployments/local/.env.example deployments/local/.env
make local-up
```

Open http://localhost:5000.

Other targets:

```bash
make local-logs
make local-ps
make local-down
make local-restart
make local-config
make smoke              # full end-to-end smoke suite (external runtime)
make smoke-postgres     # smoke suite with postgres-runtime variant
```

### Per-service development

Frontend:

```bash
cd services/ui
npm install
npm run dev
npm run lint
npm run build
```

Go proxy:

```bash
cd services/proxy
make run
make build
go test ./...
```

Python history services:

```bash
cd services/history
python -m venv venv
source venv/bin/activate
pip install -r requirements.txt
python main.py
python consumer.py
```

### Tests

Fast unit suite (no Docker required):

```bash
pip install -r services/history/requirements-dev.txt
python -m pytest tests/unit
```

PostgreSQL-backed integration suite (Docker required, uses Testcontainers):

```bash
pip install -r services/history/requirements-dev.txt
python -m pytest tests/integration -v
```

These integration tests boot an ephemeral runtime-ready PostgreSQL container,
apply `services/history/schema.sql` plus `services/runtime/sql/00_run_all.sql`,
and exercise the full history read path plus the queue-side consumer in
`services/runtime/src/runtime_consumer.py`.

## GCP VM Deployment

The VM infrastructure (GCP VMs, network, Cloud SQL, secrets) is provisioned by
the separate `gcp-terraform-bootstrap` repository. This repo owns the Ansible
that configures those VMs and ships the application onto them.

Install pinned Ansible collections:

```bash
ansible-galaxy collection install -r ansible/requirements.yml
```

Provision OS + Docker:

```bash
ansible-playbook -i ansible/inventories/gcp-vm ansible/playbooks/vm-provision.yml
```

Deploy application stack:

```bash
ansible-playbook -i ansible/inventories/gcp-vm ansible/playbooks/vm-deploy.yml
```

Secrets are read from GCP Secret Manager at deploy time and are not written to
disk. Image tag is picked through `IMAGE_TAG`:

```bash
IMAGE_TAG=dev-latest ansible-playbook -i ansible/inventories/gcp-vm ansible/playbooks/vm-deploy.yml
IMAGE_TAG=v0.1.0     ansible-playbook -i ansible/inventories/gcp-vm ansible/playbooks/vm-deploy.yml
```

See [docs/infrastructure/gcp-deployment.md](docs/infrastructure/gcp-deployment.md)
for the GCP node mapping, verification commands, and domain/HTTPS plan.

## GCP k3s Cluster Lab

A separate learning cluster runs on GCP VMs (jump host + 3 private k3s server
nodes). VM provisioning is in `gcp-terraform-bootstrap`; the Ansible automation
that installs and verifies k3s lives here.

```text
local kubectl
  -> k3s-jump public IP :6443
  -> HAProxy on k3s-jump
  -> k3s-node-1/2/3 private IP :6443
```

```bash
ansible-playbook -i ansible/inventories/gcp-k3s ansible/playbooks/k3s-cluster.yml
kubectl get nodes -o wide
kubectl -n kube-system port-forward service/headlamp 8080:80
```

See [docs/infrastructure/k3s-cluster.md](docs/infrastructure/k3s-cluster.md)
for the full runbook.

## Container Images

| Image | Build context | Notes |
| --- | --- | --- |
| Go proxy | `services/proxy/Dockerfile` | multi-stage, scratch runtime |
| History API | `services/history/Dockerfile.api` | python:3.12-slim |
| History consumer | `services/history/Dockerfile.consumer` | python:3.12-slim |
| UI | `services/ui/Dockerfile` | Node 22 builder, nginx:alpine runtime |
| Custom Postgres | `services/postgres-runtime/Dockerfile` | postgres:16 + pgmq + pg_cron |

GitHub Actions publishes images to GHCR:

```text
push to Shabat → coin-ops-*:shabat-latest
push to dev    → coin-ops-*:dev-latest
push tag v*.*  → coin-ops-*:vX.Y.Z (immutable release tag)
```

Release tags are automated from Conventional Commit squash-merges on `main`.
See [docs/deployment/release-automation.md](docs/deployment/release-automation.md).

## Public Gateway and TLS

The UI VM is the browser-facing gateway. It serves the React UI and reverse-proxies
the backend paths:

```text
https://<APP_DOMAIN>/              -> React UI
https://<APP_DOMAIN>/api/*         -> proxy VM
https://<APP_DOMAIN>/history-api/* -> history VM
```

TLS is controlled by `APP_DOMAIN` and `TLS_MODE` (`selfsigned` / `provided` /
`off`). See [docs/infrastructure/infrastructure-guide.md](docs/infrastructure/infrastructure-guide.md).

## External Data Sources

| Source | Data |
| --- | --- |
| `gamma-api.polymarket.com` | live market metadata |
| `data-api.polymarket.com` | whale leaderboard and positions |
| `api.coingecko.com` | BTC and ETH prices |
| `bank.gov.ua` | USD/UAH reference rate |

Public, unauthenticated APIs. Live behavior depends on upstream availability.

## More Detail

- [docs/architecture/overview.md](docs/architecture/overview.md) — current deployed path vs. PostgreSQL runtime target
- [docs/architecture/runtime-queue.md](docs/architecture/runtime-queue.md) — queue-side PostgreSQL runtime design
- [docs/operations/smoke-suite.md](docs/operations/smoke-suite.md) — what the smoke suite covers
- [docs/deployment/release-automation.md](docs/deployment/release-automation.md) — release-please flow
- [deprecated/](deprecated/) — frozen Hyper-V lab, kept for reference
