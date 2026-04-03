# Deployment

## VM Layout

Three Hyper-V VMs running Ubuntu 24.04 Server (no GUI):

| Hostname | Static IP | Services |
|----------|-----------|---------|
| softserve-node-01 | 172.31.1.10 | PostgreSQL · RabbitMQ · History Consumer · History API |
| softserve-node-02 | 172.31.1.11 | Proxy Service (Go) |
| softserve-node-03 | 172.31.1.12 | Web UI (nginx) |

node-01 consolidates the queue, database, and history service because only 3 VMs are available. The ТЗ marks VM4 (queue) and VM5 (DB) as optional — this is within spec.

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
nano ansible/inventory   # confirm IPs, set rabbitmq_password and db_password

# Install packages on all VMs (idempotent)
ansible-playbook -i ansible/inventory ansible/provision.yml

# Deploy all services
ansible-playbook -i ansible/inventory ansible/deploy.yml
```

Open browser → `http://172.31.1.12` → dashboard is running.

## Updating After Code Changes

```bash
git push
ansible-playbook -i ansible/inventory ansible/deploy.yml
```

`deploy.yml` syncs source files, rebuilds the Go binary, restarts services via systemd.

## Rebuilding a Destroyed VM

```bash
# 1. Fix static IP (one-time per VM — see blockers.md)

# 2. Re-provision and re-deploy
ansible-playbook -i ansible/inventory ansible/provision.yml
ansible-playbook -i ansible/inventory ansible/deploy.yml
```

## What Ansible Does

### provision.yml

| VM | Packages installed |
|----|--------------------|
| node-01 | postgresql, postgresql-contrib, rabbitmq-server, python3, python3-venv, python3-pip, python3-psycopg2 |
| node-02 | golang-go |
| node-03 | nginx |

Also creates the PostgreSQL database/user and RabbitMQ user during provisioning.

### deploy.yml (per service)

**Proxy (node-02):**
1. Creates `cognitor-proxy` system user
2. Syncs Go source to `/opt/cognitor/proxy/`
3. Runs `go build -mod=mod -o proxy .` on the VM
4. Writes `/etc/cognitor/proxy.env` (secrets, injected from inventory)
5. Writes `/etc/systemd/system/cognitor-proxy.service`
6. Reloads systemd, restarts service
7. Polls `/health` endpoint to confirm service is responding

**History (node-01):**
1. Creates `cognitor-history` system user
2. Syncs Python source to `/opt/cognitor/history/`
3. Creates venv at `/opt/cognitor/history/venv/` and installs `requirements.txt`
4. Writes `/etc/cognitor/history.env`
5. Writes two systemd units: `cognitor-history-consumer.service` and `cognitor-history-api.service`
6. Reloads and restarts both
7. Polls `/health` on history-api to confirm

**UI (node-03):**
1. Copies `ui/index.html` to `/var/www/coin-ops/`
2. Copies `ui/nginx.conf` to `/etc/nginx/sites-available/coin-ops`
3. Enables site, disables default site
4. Reloads nginx

## Service Management

```bash
# Check service status
ssh vagrant@172.31.1.11 sudo systemctl status cognitor-proxy
ssh vagrant@172.31.1.10 sudo systemctl status cognitor-history-consumer
ssh vagrant@172.31.1.10 sudo systemctl status cognitor-history-api

# Follow logs
ssh vagrant@172.31.1.11 sudo journalctl -u cognitor-proxy -f
ssh vagrant@172.31.1.10 sudo journalctl -u cognitor-history-consumer -f
ssh vagrant@172.31.1.10 sudo journalctl -u cognitor-history-api -f

# Restart a service
ssh vagrant@172.31.1.10 sudo systemctl restart cognitor-history-consumer
```

## Secrets Management

Secrets live in:
- `/etc/cognitor/proxy.env` on node-02
- `/etc/cognitor/history.env` on node-01

Both files are mode `0640`, owned by the respective service user. Ansible writes them from `ansible/inventory` variables. **Never commit real credentials to git** — `ansible/inventory` contains only the structure; override passwords before running.

## Port Summary

| VM | Port | Service |
|----|------|---------|
| node-01 | 5432 | PostgreSQL |
| node-01 | 5672 | RabbitMQ AMQP |
| node-01 | 15672 | RabbitMQ Management UI (optional) |
| node-01 | 8000 | History API |
| node-02 | 8080 | Proxy Service |
| node-03 | 80 | Web UI (nginx) |
