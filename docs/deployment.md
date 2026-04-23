# Deployment

## VM Layout

Three Hyper-V VMs running Ubuntu 24.04 Server (no GUI):

| Hostname | Static IP | Services |
|----------|-----------|---------|
| softserve-node-01 | 172.31.1.10 | PostgreSQL · History Consumer · History API |
| softserve-node-02 | 172.31.1.11 | Proxy Service (Go) |
| softserve-node-03 | 172.31.1.12 | Web UI (nginx) |

node-01 consolidates the database and history service because only 3 VMs are available. The ТЗ marks VM4 (queue) and VM5 (DB) as optional — this is within spec.

Gateway: `172.31.0.1`. Subnet: `/20`. All VMs use static IPs set via netplan.

## Prerequisites

- Python 3 + Ansible installed on your laptop/workstation
- SSH access to all three VMs (Vagrant key or your own key — set in `ansible/inventory`)
- VMs provisioned with static IPs (see [blockers.md](blockers.md) for the Hyper-V one-time fix)

## SSH Authentication Setup

Ansible authenticates to VMs using Vagrant's auto-generated SSH private keys. Key paths are machine-specific (WSL paths differ per workstation) and are stored in per-host files that are gitignored.

**Step 1 — create host_vars files for each VM:**

```bash
cp ansible/host_vars/softserve-node-01.yml.example ansible/host_vars/softserve-node-01.yml
cp ansible/host_vars/softserve-node-01.yml.example ansible/host_vars/softserve-node-02.yml
cp ansible/host_vars/softserve-node-01.yml.example ansible/host_vars/softserve-node-03.yml
```

**Step 2 — fill in the correct key path for each host:**

```yaml
# ansible/host_vars/softserve-node-01.yml
ansible_ssh_private_key_file: /mnt/f/univ/softserv-internship/.vagrant/machines/node-1/hyperv/private_key
```

Find the VM names with:
```bash
ls /mnt/f/univ/softserv-internship/.vagrant/machines/
```

**Step 3 — fix key permissions (required on WSL):**

```bash
chmod 600 /mnt/f/univ/softserv-internship/.vagrant/machines/*/hyperv/private_key
```

SSH rejects key files that are readable by other users. Vagrant regenerates keys with open permissions on every `vagrant up`, so this must be re-run after each `vagrant up`. See [blockers.md](blockers.md) blocker #12 for details.

**Step 4 — verify connectivity:**

```bash
ansible all -m ping
```

## First-Time Setup

```bash
git clone https://github.com/ua-academy-projects/coin-ops
cd coin-ops
git checkout Shabat

# Copy and fill in credentials
cp .env.example .env
nano .env   # confirm DB_PASSWORD, SSH_KEY_PATH, RUNTIME_BACKEND

# Install packages on all VMs (idempotent)
source .env
ansible-playbook -i ansible/inventory ansible/provision.yml

# Deploy all services
ansible-playbook -i ansible/inventory ansible/deploy.yml
```

Open browser → `http://172.31.1.12` → dashboard is running.

## Updating After Code Changes

```bash
git push
source .env
ansible-playbook -i ansible/inventory ansible/deploy.yml
```

`deploy.yml` pulls updated container images and restarts services via Docker Compose.

## Rebuilding a Destroyed VM

```bash
# 1. Fix static IP (one-time per VM — see blockers.md)

# 2. Re-provision and re-deploy
source .env
ansible-playbook -i ansible/inventory ansible/provision.yml
ansible-playbook -i ansible/inventory ansible/deploy.yml
```

## What Ansible Does

### provision.yml

Installs Docker and common packages on all VMs. Creates data directories for PostgreSQL on node-01.

### deploy.yml (per service)

**History (node-01):**
1. Stops legacy host services (if present)
2. Writes `/etc/cognitor/history.env` (secrets from `.env`)
3. Renders Docker Compose file from template
4. Starts PostgreSQL first, waits for readiness
5. Applies runtime schema
6. Starts all containers (`postgres`, `history-consumer`, `history-api`)
7. Polls `/health` on history-api to confirm

**Proxy (node-02):**
1. Stops legacy host services (if present)
2. Writes `/etc/cognitor/proxy.env` (secrets from `.env`)
3. Renders Docker Compose file from template
4. Pulls and starts proxy container
5. Polls `/health` endpoint to confirm service is responding

**UI (node-03):**
1. Renders Docker Compose file from template
2. Pulls and starts UI container
3. Polls health endpoint to confirm

## Service Management

```bash
# Check container status
ssh vagrant@172.31.1.11 docker compose -f /opt/cognitor/proxy/compose.yaml ps
ssh vagrant@172.31.1.10 docker compose -f /opt/cognitor/history/compose.yaml ps

# Follow logs
ssh vagrant@172.31.1.11 docker compose -f /opt/cognitor/proxy/compose.yaml logs -f proxy
ssh vagrant@172.31.1.10 docker compose -f /opt/cognitor/history/compose.yaml logs -f history-consumer

# Restart a service
ssh vagrant@172.31.1.10 docker compose -f /opt/cognitor/history/compose.yaml restart history-consumer
```

## Secrets Management

Secrets live in:
- `/etc/cognitor/proxy.env` on node-02
- `/etc/cognitor/history.env` on node-01

Both files are mode `0640`, owned by root. Ansible writes them from environment variables loaded via `source .env`. **Never commit real credentials to git** — `.env` is gitignored.

## Port Summary

| VM | Port | Service |
|----|------|---------|
| node-01 | 5432 | PostgreSQL |
| node-01 | 8000 | History API |
| node-02 | 8080 | Proxy Service |
| node-03 | 80 | Web UI (nginx) |
