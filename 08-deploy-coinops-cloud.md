# Task 08 — Deploy CoinOps on AWS Cloud

**Date:** 07.05.2026  
**Source:** Meeting 04.05.2026 (mentor Pavlo Pylypiuk) + team notes  
**Branch:** `dev-penina-cloud` (off `dev`)  
**Cloud:** AWS  
**Runtime:** `external` (RabbitMQ + Redis)  
**Status:** In progress

---

## Previous Task: Cloud_Multi Modules ✅ DONE

All 7 mentor requirements passed. Terraform at `terraform/` supports both AWS and GCP via `config.yaml` cloud switching.

---

## Goal

Deploy the CoinOps application (`dev` branch) on AWS VMs created by Terraform. Application runs in Docker containers, distributed across VMs, accessible via HTTPS on a custom domain.

---

## What Already Exists

### Docker Images on GHCR (built by CI)

| Package | Image |
|---------|-------|
| coin-ops-ui | `ghcr.io/ua-academy-projects/coin-ops-ui` |
| coin-ops-proxy | `ghcr.io/ua-academy-projects/coin-ops-proxy` |
| coin-ops-history-api | `ghcr.io/ua-academy-projects/coin-ops-history-api` |
| coin-ops-history-consumer | `ghcr.io/ua-academy-projects/coin-ops-history-consumer` |

Tags: `dev-latest`, `shabat-latest`, `v0.1.0`

### Ansible Pipeline (from `dev`)

| File | Purpose |
|------|---------|
| `ansible/provision.yml` | Install Docker on all VMs |
| `ansible/deploy.yml` | Deploy containers via Jinja2-templated docker-compose |
| `ansible/roles/common/` | Base packages, users |
| `ansible/roles/docker/` | Docker Engine installation |
| `ansible/roles/history/` | History node: compose + env templates |

### Environment Variables

**Core:**

| Variable | Example |
|----------|---------|
| `RUNTIME_BACKEND` | `external` |
| `DATABASE_URL` | `postgresql://cognitor:pass@<DB_HOST>:5432/cognitor` |

**External mode:**

| Variable | Example |
|----------|---------|
| `RABBITMQ_URL` | `amqp://user:pass@<HOST>:5672/` |
| `RABBITMQ_DEFAULT_USER` | `cognitor` |
| `RABBITMQ_DEFAULT_PASS` | `password` |
| `REDIS_URL` | `redis://<HOST>:6379` |

**Per-service:** `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB`, `PORT`, `PROXY_URL`, `HISTORY_URL`

---

## AWS Architecture

| VM | Role | Containers |
|----|------|------------|
| jump-host | SSH gateway (public IP, port 9922) | — |
| node-01 | History + data | PostgreSQL, RabbitMQ, history-consumer, history-api |
| node-02 | Proxy + cache | Go proxy, Redis |
| node-03 | Frontend (public IP for HTTPS) | nginx + React SPA |
| **Optional:** AWS RDS | Managed DB | PostgreSQL (not containerized) |

---

## Implementation Steps

### Step 1 — Branch and workspace ✅ DONE

- Created `dev-penina-cloud` off `dev`
- Replaced Hyper-V terraform with multicloud AWS/GCP modules at `terraform/`
- Clean structure on GitHub

### Step 2 — Register domain (DO THIS FIRST — DNS takes time)

1. Go to nick.ua — register a free `.pp.ua` domain
2. Confirm via Telegram bot
3. Register on Cloudflare (free account)
4. Transfer domain nameservers to Cloudflare

### Step 3 — Adapt Terraform for app deployment

Current `terraform/config.yaml` creates: jump-host + 3 generic internal VMs.

**What needs to change:**
- Rename VMs to app roles: node-01 (history), node-02 (proxy), node-03 (ui)
- Set `cloud: "aws"` in config
- Add firewall rules for app ports (5672 RabbitMQ, 8080 proxy, 5432 PostgreSQL, 80/443 HTTPS)
- node-03 needs a public IP for HTTPS traffic
- Output all internal IPs for Ansible inventory
- Optional: add AWS RDS module for managed PostgreSQL

### Step 4 — Set up Ansible inventory

After `terraform apply`, Ansible needs the VM IPs.

**Phase 1 (start here):** Static inventory — copy IPs from `terraform output` manually:
```ini
[history]
<NODE-01-INTERNAL-IP> ansible_user=marta_ops ansible_port=9922

[proxy]
<NODE-02-INTERNAL-IP> ansible_user=marta_ops ansible_port=9922

[ui]
<NODE-03-INTERNAL-IP> ansible_user=marta_ops ansible_port=9922
```

**Phase 2 (goal):** Dynamic inventory from Terraform outputs.

### Step 5 — Adapt Ansible for AWS VMs

The `dev` Ansible expects Hyper-V VMs on `172.31.x.x`. Adapt:
- SSH connection: `marta_ops`, port `9922`, your SSH key
- Env var values: DB host, RabbitMQ host = internal IPs from Terraform
- Docker Compose templates: use GHCR images with `IMAGE_TAG=dev-latest`

### Step 6 — Deploy and test

```bash
source .env
ansible-playbook -i ansible/inventory ansible/provision.yml
IMAGE_TAG=dev-latest ansible-playbook -i ansible/inventory ansible/deploy.yml
```

Verify: SSH into VMs, check `docker ps`, test cross-VM communication.

### Step 7 — SSL certificate with Certbot

Method: DNS challenge via Cloudflare (no ports needed during validation).  
**Use `--staging` first** — Let's Encrypt rate-limits production certs.

### Step 8 — Expose app via HTTPS

nginx on node-03 terminates SSL on port 443. Cloudflare DNS A record points to node-03's public IP.

---

## What NOT To Do

- **Docker Swarm** — mentor says use Kubernetes if you need orchestration
- **Autoscaling groups** — not needed
- **Packer** — wrong stage
- **Build images locally** — use GHCR images from CI

## Bonus (if time allows)

- Tailscale overlay network between VMs
- Cloudflare Tunnel + GitHub OAuth
- Dynamic Ansible inventory from Terraform outputs
- AWS RDS instead of containerized PostgreSQL

---

## Acceptance Criteria

- [ ] Domain registered on pp.ua, managed via Cloudflare
- [ ] Terraform creates all AWS VMs in one `apply`
- [ ] Ansible inventory has correct IPs
- [ ] `ansible-playbook provision.yml` installs Docker on all VMs
- [ ] `ansible-playbook deploy.yml` starts all containers with correct env vars
- [ ] Containers on different VMs communicate (proxy → RabbitMQ, history → DB)
- [ ] SSL certificate obtained via Certbot DNS challenge
- [ ] Application accessible via HTTPS on the domain
- [ ] Browser shows live coin rates and historical data
