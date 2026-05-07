# Task 08 — Deploy CoinOps Application on Cloud Infrastructure

**Date:** 07.05.2026  
**Source:** Meeting 04.05.2026 (mentor Pavlo Pylypiuk) + friend's notes  
**Status:** Starting

---

## Part A — Previous Task Review: Cloud_Multi Modules

### Mentor's 7 Requirements vs My Implementation

| # | Requirement | Status | Notes |
|---|-------------|--------|-------|
| 1 | One Terraform root | ✅ PASS | Single `main.tf` calls all modules |
| 2 | One config file | ✅ PASS | Single `config.yaml` with `cloud: "gcp"` or `"aws"` |
| 3 | Size dictionary | ✅ PASS | `sizes.small.gcp: "e2-micro"`, VMs reference `size: small` |
| 4 | Cloud switching logic inside modules | ✅ PASS | `count = var.cloud == "gcp" ? 1 : 0` pattern in every module |
| 5 | Internal IPs in outputs | ✅ PASS | Both `gcp_vm` and `aws_vm` modules output `internal_vm_ips` |
| 6 | Default values with override | ✅ PASS | `try(each.value.disk_size, var.default_disk)` pattern |
| 7 | No hardcoding | ✅ PASS | Everything from `config.yaml` or variables |

### What Other Students Did Wrong (from meeting)

- **Maksym:** Two providers in one file but each VM described separately per cloud — no abstraction, just copy-paste. Unused local variables.
- **Valentin:** Two separate directories for AWS and GCP — two Terraform roots instead of one.
- **Artur:** Two separate variable blocks. No internal IP outputs.
- **Volodymyr (Shabat):** Two root files instead of one. Tried ternary but couldn't make one module skip execution.

### Closest to correct: Vasyl

Vasyl's approach matches what I implemented — the module itself checks which cloud to use and decides whether to create resources. Mentor confirmed this is the right pattern.

### Conclusion

My Cloud_Multi implementation matches all mentor requirements. **This task is done.** Moving to the new task.

---

## Part B — New Task: Deploy CoinOps on Cloud

### Assignment Summary

Deploy the CoinOps application (from `dev` branch) on cloud infrastructure created by Terraform. Application must be in Docker containers, distributed across VMs, accessible via a domain with HTTPS.

### Key Requirements

1. **One Terraform script** launches the entire infrastructure (VMs + networking + managed DB)
2. **Deploy the `dev` branch** of coin-ops on cloud
3. **Managed cloud database** — use the cloud provider's managed PostgreSQL (GCP Cloud SQL or AWS RDS), not a self-hosted PostgreSQL VM
4. **Minimum 2 VMs with containers** — services must communicate across different machines
5. **1 VM (or managed service) for database**
6. **Docker containers** — application packaged in Docker images
7. **Ansible** configures VMs after Terraform creates them
8. **Domain** — register free domain on pp.ua (requires Telegram confirmation)
9. **Cloudflare** — transfer domain to Cloudflare nameservers, manage DNS there
10. **SSL certificate** — Certbot with DNS challenge via Cloudflare for HTTPS

### Which Cloud?

**TBD — needs clarification.** Friend's notes say "YAML config users → AWS." I used YAML config. But the meeting summary says "deploy on GCP infrastructure you already created." My Cloud_Multi supports both — I need to pick one.

### CoinOps Architecture on `dev` Branch

Current `dev` branch uses 3 nodes:

| Node | IP | Containers |
|------|-----|------------|
| node-01 | 172.31.1.10 | PostgreSQL, RabbitMQ, history-consumer (Python/pika), history-api (FastAPI) |
| node-02 | 172.31.1.11 | Go proxy, Redis |
| node-03 | 172.31.1.12 | nginx gateway + React SPA |

Data flow:
```
Browser → nginx (node-03) → /api → Go proxy (node-02) → CoinGecko/NBU APIs
                                                       → publishes to RabbitMQ (node-01)
                                                       → Python consumer → PostgreSQL
         nginx (node-03) → /history-api → FastAPI (node-01) → reads from PostgreSQL → browser
```

### Cloud Deployment Plan — Proposed VM Layout

Since the task requires managed DB, PostgreSQL moves out of the VMs:

| VM | Role | Containers |
|----|------|------------|
| jump-host | SSH gateway only | none (or Ansible control) |
| app-vm-1 | Backend services | RabbitMQ, history-consumer, history-api (FastAPI) |
| app-vm-2 | Proxy + cache | Go proxy, Redis |
| app-vm-3 | Frontend | nginx + React SPA |
| Managed DB | Cloud SQL / RDS | PostgreSQL (managed, not containerized) |

This satisfies: minimum 2 VMs with containers communicating across machines, plus managed database.

---

## Step-by-Step Approach

### Step 1 — Terraform Infrastructure

Extend Cloud_Multi to also create:
- Managed PostgreSQL instance (Cloud SQL for GCP / RDS for AWS)
- Firewall rules allowing container communication between VMs
- Output all internal IPs for Ansible inventory

**What I need to figure out:**
- How to add a managed DB module to Cloud_Multi
- How to output the DB connection string for application use

### Step 2 — Ansible Inventory from Terraform

Two options (start simple, improve later):
- **Option A (start here):** Static inventory — copy IPs from `terraform output` into Ansible inventory manually
- **Option B (goal):** Dynamic inventory — Terraform writes outputs, script/plugin generates Ansible inventory automatically

Mentor called dynamic inventory "шикарна практика" — aim for Option B.

### Step 3 — Ansible Playbook: Install Docker

Ansible roles needed:
- `common` — base packages, users, SSH config
- `docker` — install Docker Engine + Docker Compose on each VM
- `deploy` — place docker-compose files and start containers

### Step 4 — Docker Compose per VM

Each VM gets its own `docker-compose.yml` (or Ansible templates them). Containers need to know:
- Internal IPs of other VMs (for cross-VM communication)
- Managed DB connection string
- RabbitMQ credentials

### Step 5 — Domain

1. Register on pp.ua — get a free `.pp.ua` domain
2. Confirm via Telegram bot
3. Register on Cloudflare (free account)
4. Transfer domain to Cloudflare nameservers

### Step 6 — SSL Certificate

Tool: **Certbot** (Let's Encrypt)  
Method: **DNS challenge via Cloudflare** — no need to open port 80/443 during validation

**Important:** Test on staging first (`--staging` flag) — Let's Encrypt has rate limits on production certificates. Staging gives invalid certs (browser warning) but same mechanism. Switch to production when it works.

### Step 7 — Expose Application

Without load balancer: nginx listens on port 443 with the SSL certificate directly. Port 80 without a load balancer is not recommended per mentor.

---

## What NOT To Do

- **Docker Swarm** — mentor said "unnecessary work", real projects go straight to Kubernetes
- **Autoscaling groups** — not needed for this task
- **Packer** — interesting but not for this stage

## Bonus Topics (Optional)

- **Tailscale** — overlay network between VMs, no port opening needed, Ansible role available
- **Cloudflare Tunnel** — expose service without opening any ports, DNS challenge for certs, GitHub OAuth for access control

---

## Open Questions

1. Which cloud? GCP or AWS? (need to clarify with team)
2. Are Docker images already on GHCR from CI, or do I build locally?
3. What env vars / secrets does the `dev` branch need? (DATABASE_URL, RABBITMQ_URL, RUNTIME_BACKEND, etc.)
4. Is `dev` branch stable right now, or are there active PRs that need to merge first?
5. Does the managed DB need to be created with the same name as the project database?

---

## Dependencies

- Cloud_Multi Terraform working ✅
- `dev` branch Docker images
- pp.ua domain registration
- Cloudflare account
- Certbot installed on one VM
