# CoinOps — Coin Rates Dashboard

A multi-VM application that fetches live cryptocurrency and currency exchange rates, displays them in a React dashboard, and stores historical data asynchronously.

## Architecture

| VM | Service | IP (Host-Only) | Language |
|---|---|---|---|
| server1 | UI Service (Flask + React) | 192.168.56.101 | Python |
| server2 | Proxy/API Service + Redis cache | 192.168.56.102 | Python |
| server3 | Message Queue (RabbitMQ) | 192.168.56.103 | — |
| server4 | History Service | 192.168.56.104 | Go |
| server5 | Database (PostgreSQL) | 192.168.56.105 | — |

## Data Flow

```
User opens browser
  → Flask serves React UI (server1)
  → React fetches from Proxy (server2)
  → Proxy checks Redis cache → if fresh, returns immediately
  → If cache miss → Proxy calls CoinGecko and NBU APIs
  → Proxy publishes to RabbitMQ (server3)
  → Go service consumes from queue (server4)
  → Go saves to PostgreSQL (server5)
  → React fetches history from Flask (server1)
```

## Data Sources

- **Crypto:** CoinGecko API (Bitcoin, Ethereum in USD and UAH)
- **Currency:** NBU API (~40 currencies)

## Features

- Live Bitcoin and Ethereum prices with charts
- Price change indicator since first record
- Currency selector from full NBU list
- Auto-refresh every 30 seconds with countdown
- History table with pagination
- Service status monitoring panel
- 25-second Redis cache on proxy (survives service restarts)

## Tech Stack

- **Frontend:** React + Vite + Recharts
- **UI Backend:** Python / Flask
- **Proxy:** Python / Flask + Redis cache
- **History Service:** Go
- **Message Queue:** RabbitMQ
- **Database:** PostgreSQL

---

## Iteration 1 — Ansible VM Deployment

All services deployed on Ubuntu 24.04 VMs using Ansible automation.

### Requirements

- Ansible installed on server1
- SSH key access from server1 to all VMs
- Passwordless sudo on all VMs

### Deploy Everything

```bash
cd ansible
ansible-playbook -i inventory.ini site.yml
```

### Deploy Individual Service

```bash
ansible-playbook -i inventory.ini playbooks/server1.yml
ansible-playbook -i inventory.ini playbooks/server2.yml
ansible-playbook -i inventory.ini playbooks/server03.yml
ansible-playbook -i inventory.ini playbooks/server4.yml
ansible-playbook -i inventory.ini playbooks/server5.yml
```

### Service Management

All services managed by systemd — start automatically on boot, restart on crash.

```bash
sudo systemctl status ui-service
sudo systemctl status proxy-service
sudo systemctl status history-service
sudo systemctl status rabbitmq-server
sudo systemctl status postgresql
```

---

## Iteration 2 — Docker Compose

Services containerized and run together on server1 using Docker Compose.
PostgreSQL stays on server5 VM — databases should not run in disposable containers.

### Run with Docker Compose

```bash
cd docker/
docker compose up --build   # first time
docker compose up           # subsequent runs
docker compose down         # stop everything
```

Open: `http://192.168.56.101:8080`

### Container Architecture

```
server1 (Docker host)
  ├── container: ui       — React + Flask (port 8080)
  ├── container: proxy    — Flask + Redis (port 5000)
  ├── container: rabbitmq — Message queue (port 5672)
  ├── container: redis    — Cache
  └── container: history  — Go consumer
server5 (VM) — PostgreSQL
```

---

## Documentation

| Doc | Description |
|---|---|
| [docs/01-vm-setup.md](docs/01-vm-setup.md) | Iteration 1: VMs, Ansible, systemd, blockers |
| [docs/02-redis-cache.md](docs/02-redis-cache.md) | Feature: Redis replacing in-memory Python cache |
| [docs/03-docker.md](docs/03-docker.md) | Iteration 2: Docker Compose, Dockerfiles, mistakes |
| [docs/04-next-steps.md](docs/04-next-steps.md) | Planned: Swarm, CI/CD, Nginx, HTTPS |

---

## VM Setup Notes

- server1, server4, server5 — created manually in VirtualBox with Ubuntu 24.04
- server2 — created with Vagrant (ubuntu/jammy64)
- server03 — recreated as manual VirtualBox VM (Vagrant caused disk issues)
- All VMs use two adapters: Bridged (internet) + Host-Only (stable static IPs)

## Blockers and Workarounds

- **RabbitMQ slow install** — VM was paused in VirtualBox, resumed and completed
- **Node.js version** — upgraded from EOL Node 18 to Node 20 LTS using NVM
- **CoinGecko rate limiting** — added 25-second Redis cache to proxy
- **Python package conflicts** — used virtualenv instead of system pip
- **Vagrant SSH** — server03 uses key-only auth, manually added Ansible key
- **Unattended upgrades lock** — killed background apt process blocking Ansible
- **server03 disk missing** — Vagrant VMDK lost after crash, recreated as VirtualBox VM
