# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Architecture

Three services across three Hyper-V VMs on an internal switch (172.31.0.0/20):

| VM | IP | Service |
|----|-----|---------|
| node-01 | 172.31.1.10 | History consumer + FastAPI + PostgreSQL + RabbitMQ |
| node-02 | 172.31.1.11 | Go proxy + Redis |
| node-03 | 172.31.1.12 | React SPA + nginx |

**Data flow:** Browser → nginx (node-03:80) → Go proxy (node-02:8080) → Polymarket/CoinGecko/NBU APIs → publishes to RabbitMQ → Python consumer (node-01) inserts into PostgreSQL → History API (node-01:8000) serves historical data back to browser.

**Proxy** (`proxy/main.go`) — stateless Go service. Fetches 20 live Polymarket markets, whale leaderboard, and BTC/ETH/UAH prices. Caches whales (5 min) and prices (60s). Publishes market and price events to RabbitMQ. Stores session state in Redis (non-critical; 503 if Redis unavailable).

**History** (`history/`) — two Python processes sharing the same codebase:
- `consumer.py` — pika RabbitMQ consumer, routes by `type` field: market events → `market_snapshots`, price events → `price_snapshots`. Idempotent writes via `ON CONFLICT DO NOTHING`.
- `main.py` — FastAPI server on port 8000 with endpoints: `/history`, `/history/{slug}`, `/prices/history/{coin}`, `/health`.

**UI** (`ui-react/`) — React + Vite + Recharts SPA. Service URLs come from Vite env vars (`VITE_PROXY_URL`, `VITE_HISTORY_URL`) written by Ansible at build time.

## Commands

### Proxy (Go)
```bash
cd proxy
make build    # cross-compile → proxy-linux (GOOS=linux GOARCH=amd64)
make run      # local run
make tidy     # go mod tidy
```

### UI (React)
```bash
cd ui-react
npm run dev      # dev server on :3000
npm run build    # production build → dist/
npm run lint     # tsc --noEmit
```

### History (Python)
No local runner — deploy via Ansible or run manually: `python3 main.py` / `python3 consumer.py`.

## Deployment

**Prerequisites:** `source .env` before any Ansible or Terraform command.

```bash
# First-time VM provisioning
terraform -chdir=terraform apply

# OS setup (Go, Python, PostgreSQL, RabbitMQ, UFW)
ansible-playbook -i ansible/inventory ansible/provision.yml

# Deploy / update all services
ansible-playbook -i ansible/inventory ansible/deploy.yml

# Redeploy a single service
ansible-playbook -i ansible/inventory ansible/deploy.yml --limit softserve-node-02,localhost
# Note: always include 'localhost' when limiting — the React build runs on localhost
```

Ansible builds the React app on `localhost`, syncs `dist/` to node-03, builds the Go binary on node-02, and deploys Python to node-01. Service configs land in `/etc/cognitor/` on each VM; systemd units are managed by Ansible.

## Infrastructure Details

- **Terraform** uses WinRM to talk to the Windows Hyper-V host. Provider: `taliesins/hyperv`.
- **Secrets** flow: `.env` → Ansible group_vars (`lookup('env', ...)`) → written to `/etc/cognitor/*.env` on VMs at deploy time. Never hardcoded.
- **WSL chmod** on `/mnt/f/` requires `/etc/wsl.conf` with `[automount] options = "metadata"`, otherwise chmod is a no-op and SSH rejects the key.
- **After terraform destroy+apply:** re-run `New-NetIPAddress` + `New-NetNat` in PowerShell Admin (switch loses host IP), and `ssh-keygen -R 172.31.1.{10,11,12}` (host keys change).
- Base VHDX must be pre-resized to ≥20 GB with `Resize-VHD` in PowerShell Admin before `terraform apply`. Cloud-init `growpart` expands the partition automatically on first boot.
- Hyper-V Gen 2 Secure Boot requires `MicrosoftUEFICertificateAuthority` template (not the default `MicrosoftWindows`).

## Database Schema

Tables in PostgreSQL on node-01 (`history/schema.sql`):
- `market_snapshots` — one row per market per `/current` call; UNIQUE(slug, fetched_at)
- `price_snapshots` — BTC/ETH/USD_UAH prices; UNIQUE(coin, fetched_at)
- `whales`, `whale_positions` — leaderboard + open positions

## Known Provider Quirks (taliesins/hyperv Terraform provider)

- `enable_secure_boot` expects `"On"`/`"Off"` strings, not booleans.
- MAC address: must set both `static_mac_address` AND `dynamic_mac_address = false`.
- Memory: use either `dynamic_memory = true` OR `static_memory = true`, never both.
- Stop VMs before `terraform apply` when changing hardware (DVD drive resource pool lock).
