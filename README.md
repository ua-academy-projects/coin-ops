# CoinOps — Cloud Deployment

Personal cloud deployment branch: `dev-penina-cloud`
Owner: Marta Penina (@MartaPenina)
Based on: `dev` branch of [ua-academy-projects/coin-ops](https://github.com/ua-academy-projects/coin-ops)

---

## What This Branch Does

Deploys the CoinOps application to AWS + Azure (hybrid multi-cloud) and a k3s Kubernetes cluster on GCP using:
- **Terraform** — provisions cloud infrastructure across Azure + AWS + GCP
- **Ansible** — configures VMs, deploys containers, installs k3s cluster and apps
- **Docker Compose** — runs services on each VM (hybrid)
- **Tailscale** — overlay VPN with subnet router pattern connecting VMs across clouds
- **k3s** — lightweight Kubernetes cluster on GCP
- **Helm** — installs Kubernetes apps (cert-manager, Headlamp, Homepage)
- **Cloudflare** — DNS + HTTPS proxy

## Application

Coin rates monitoring dashboard:
- Live BTC, ETH prices from CoinGecko
- USD/UAH rate from NBU
- Historical data charts
- Hybrid app: `https://coinops-softserve-penina.pp.ua` ✅
- k3s Homepage: `https://k3s.coinops-softserve-penina.pp.ua` ✅
- k3s Headlamp: `https://headlamp.coinops-softserve-penina.pp.ua` ✅

---

## Architecture

### Hybrid Azure + AWS (Task 1)

```
Internet
  │
  ▼
Cloudflare (HTTPS proxy, coinops-softserve-penina.pp.ua)
  │
  ▼
Azure Load Balancer (20.91.139.85)
  │
  ▼
node-03 — nginx + React UI     (Azure swedencentral, private IP 10.0.4.4)
  │
  │  [Tailscale subnet router tunnel — gateway-aws ↔ gateway-azure]
  │
  ├── /api/         → node-02 — Go proxy + Redis   (AWS eu-central-1, 10.0.2.78)
  │                     │
  │                     └── publishes → node-01 — RabbitMQ + History API
  │                                         │       (AWS eu-central-1, 10.0.2.100)
  │                                         └── AWS RDS PostgreSQL (private subnet)
  │
  └── /history-api/ → node-01 — History API (AWS eu-central-1, 10.0.2.100)

SSH: Your machine → jump-host (AWS, port 9922, 3.70.205.142) → nodes via ProxyJump
Cross-cloud SSH:  jump-host → gateway-aws → Tailscale → node-03 (Azure)
```

### GCP k3s Cluster (Task 2 + Task 3)

```
Internet
  │
  ▼
Cloudflare (DNS only)
  │
  ▼
34.158.238.181 (k3s-server-1, GCP europe-central2)
  │
  ▼
Traefik Ingress (built into k3s)
  │
  ├── k3s.coinops-softserve-penina.pp.ua      → Homepage pod
  └── headlamp.coinops-softserve-penina.pp.ua → Headlamp pod

GCP k3s Cluster:
  k3s-server-1 (control plane + worker, public IP 34.158.238.181 / 10.0.1.11)
  k3s-server-2 (control plane + worker, private 10.0.1.12)
  k3s-server-3 (control plane + worker, private 10.0.1.13)

cert-manager → Let's Encrypt TLS certificates (auto-renewed)
```

---

## Cloud Status

| Cloud | Infrastructure | Ansible | App | URL |
|-------|---------------|---------|-----|-----|
| **Azure+AWS Hybrid** | ✅ Complete | ✅ Complete | ✅ Live | coinops-softserve-penina.pp.ua |
| **GCP k3s** | ✅ Complete | ✅ Complete | ✅ Live | k3s.coinops-softserve-penina.pp.ua |

---

## Hybrid Azure + AWS (Task 1)

### VM Distribution

| VM | Cloud | Region | Role | IP |
|----|-------|--------|------|----|
| jump-host | AWS | eu-central-1 | SSH entry point | 3.70.205.142 (public) |
| gateway-aws | AWS | eu-central-1 | Tailscale subnet router | 10.0.1.145 (private) |
| node-01 | AWS | eu-central-1 | RabbitMQ + History API | 10.0.2.100 (private) |
| node-02 | AWS | eu-central-1 | Go proxy + Redis | 10.0.2.78 (private) |
| RDS PostgreSQL | AWS | eu-central-1 | Managed database | private subnet |
| gateway-azure | Azure | swedencentral | Tailscale subnet router | 135.225.57.231 (public) |
| node-03 | Azure | swedencentral | nginx + React UI | 10.0.4.4 (private, behind LB) |
| Azure LB | Azure | swedencentral | Load Balancer | 20.91.139.85 (public) |
| Terraform state | GCP | europe-central2 | State storage | gs://devops-intern-penina-tf-state |

### Tailscale Subnet Router Pattern

See [tailscale-subnet-router.md](tailscale-subnet-router.md) for full explanation.

Summary: instead of installing Tailscale on every VM, one dedicated gateway VM per network acts as subnet router. It advertises its entire subnet to the Tailscale network. Other VMs need no Tailscale installed.

```
AWS VPC
  gateway-aws  (Tailscale ON, advertises 10.0.1.0/24, 10.0.2.0/24)
    ├── node-01 (Tailscale OFF — reachable via gateway-aws route)
    └── node-02 (Tailscale OFF — reachable via gateway-aws route)

Azure VNet
  gateway-azure (Tailscale ON, advertises 10.0.4.0/24)
    └── node-03  (Tailscale OFF — reachable via gateway-azure route)
```

---

## GCP k3s Cluster (Task 2 + Task 3)

### VM Distribution

| VM | Role | IP |
|----|------|----|
| k3s-server-1 | control plane + worker | 34.158.238.181 (public) / 10.0.1.11 |
| k3s-server-2 | control plane + worker | 10.0.1.12 (private) |
| k3s-server-3 | control plane + worker | 10.0.1.13 (private) |

### Ansible Roles

| Role | Purpose |
|------|---------|
| `k3s_prereqs` | curl, Helm, pip3, python kubernetes library |
| `k3s_server_bootstrap` | initializes cluster on node-1, sets TLS SAN |
| `k3s_server_join` | joins node-2 and node-3 to cluster |
| `k3s_postcheck` | verifies all nodes Ready, downloads kubeconfig |
| `cert_manager` | installs cert-manager + Let's Encrypt ClusterIssuer |
| `k3s_headlamp` | installs Headlamp UI + Ingress + TLS |
| `k3s_homepage` | installs Homepage dashboard + Ingress + TLS |

### Playbooks

```bash
# Bootstrap k3s cluster
ansible-playbook -i ansible/inventory ansible/k3s-cluster.yml

# Install apps (cert-manager, Headlamp, Homepage)
ansible-playbook -i ansible/inventory ansible/k3s-apps.yml
```

### kubectl Access

```bash
export KUBECONFIG=/d/.ssh/k3s-config.yaml
kubectl get nodes
```

---

## Quick Start — Hybrid (Azure + AWS)

```bash
# 1. Set credentials in terraform/terraform.tfvars

# 2. Init and apply Terraform
cd terraform
terraform init -reconfigure
terraform apply -auto-approve

# 3. SSH to jump-host
eval $(ssh-agent -s)
ssh-add /d/.ssh/id_ed25519_devops
ssh -A -p 9922 marta_ops@3.70.205.142

# 4. On jump-host: pull repo and provision
cd coin-ops && git pull origin dev-penina-cloud
source .env
ansible-playbook -i ansible/inventory ansible/provision.yml --limit 'all:!node-03'
ansible-playbook -i ansible/inventory ansible/provision.yml --limit node-03
ansible-playbook -i ansible/inventory ansible/deploy.yml
```

## Quick Start — GCP k3s

```bash
# After terraform apply (GCP VMs already created)

# On jump-host:
source .env
ansible-playbook -i ansible/inventory ansible/k3s-cluster.yml
ansible-playbook -i ansible/inventory ansible/k3s-apps.yml

# On local machine:
scp -P 9922 marta_ops@3.70.205.142:/tmp/k3s-config.yaml /d/.ssh/k3s-config.yaml
export KUBECONFIG=/d/.ssh/k3s-config.yaml
kubectl get nodes
```

---

## Ansible Inventory Structure

```ini
[gateway]
gateway-azure  ansible_host=135.225.57.231  subnet_cidr=10.0.4.0/24
gateway-aws    ansible_host=10.0.1.145      subnet_cidr=10.0.1.0/24,10.0.2.0/24

[jump_host]
jump-host  ansible_host=3.70.205.142

[history]
node-01  ansible_host=10.0.2.100

[proxy]
node-02  ansible_host=10.0.2.78

[ui]
node-03  ansible_host=10.0.4.4

[aws_internal:children]
history
proxy

[aws_internal:vars]
ansible_ssh_common_args=-o ProxyJump=marta_ops@3.70.205.142:9922 -o StrictHostKeyChecking=no

[azure_internal:children]
ui

[azure_internal:vars]
ansible_ssh_common_args=-o ProxyJump=marta_ops@10.0.1.145:9922 -o StrictHostKeyChecking=no

[k3s_bootstrap]
k3s-server-1  ansible_host=34.158.238.181

[k3s_join]
k3s-server-2  ansible_host=10.0.1.12
k3s-server-3  ansible_host=10.0.1.13

[k3s_server:children]
k3s_bootstrap
k3s_join

[k3s_server:vars]
common_allowed_ports=["9922", "6443", "9345", "10250", "2379", "2380"]
common_allowed_udp_ports=["8472"]

[k3s_join:vars]
ansible_ssh_common_args=-o ProxyJump=marta_ops@34.158.238.181:9922 -o StrictHostKeyChecking=no

[all:vars]
ansible_user=marta_ops
ansible_port=9922
ansible_ssh_private_key_file=~/.ssh/id_ed25519
ansible_ssh_common_args=-o StrictHostKeyChecking=no
```

---

## Problems & Solutions

### Task 1

**Problem 1 — Azure vCPU quota limit**
3 Azure VMs needed 6 vCPU, quota only 4.
Fix: moved jump-host to AWS. Azure now has only gateway-azure + node-03 = 4 vCPU.

**Problem 2 — Tailscale `creates:` idempotency bug**
Task used `creates:` — file existed after first run, command always skipped.
Fix: replaced with `register/changed_when` pattern.

**Problem 3 — Both gateways advertising same CIDR 10.0.0.0/16**
Tailscale got confused which gateway owns which subnet.
Fix: split into specific CIDRs per gateway.

**Problem 4 — node-03 unreachable via ProxyJump through jump-host**
jump-host (AWS) cannot reach 10.0.4.x (Azure) — no Tailscale on jump-host.
Fix: node-03 uses ProxyJump through gateway-aws which has Tailscale route to Azure.

### Task 2 + Task 3

**Problem 5 — GCP startup script CRLF line endings**
GCP could not execute script: `cannot execute: required file not found`
Fix: separate `startup.sh` file + `.gitattributes` `*.sh eol=lf`

**Problem 6 — Private GCP nodes had no internet access**
k3s-server-2/3 could not run apt install.
Fix: added Cloud NAT + Cloud Router.

**Problem 7 — k3s join used public IP instead of private**
k3s-server-2/3 tried to connect via 34.158.238.181 — blocked by GCP firewall.
Fix: `k3s_server_ip` fact uses `ansible_default_ipv4.address` (private IP).

**Problem 8 — kubectl TLS certificate mismatch**
k3s TLS cert only valid for private IPs, kubectl connects via public IP.
Fix: `--tls-san {{ ansible_host }}` in bootstrap install command.

**Problem 9 — UFW blocked k3s inter-node ports**
common role only opened 9922. k3s needs 6443, 9345, 2379-2380, 8472 UDP, 10250.
Fix: `common_allowed_ports` override in `[k3s_server:vars]`.

**Problem 10 — Let's Encrypt rejected email**
`marta.penina@devops` — domain `.devops` does not exist.
Fix: changed to `marta.penina.academic@gmail.com`.

**Problem 11 — Homepage "Host validation failed"**
Homepage validates Host header, rejects unknown domains.
Fix: `HOMEPAGE_ALLOWED_HOSTS` env variable in Helm values.

---

## Secrets — Never Commit

| File | Contains | Gitignored |
|------|---------|-----------|
| `.env` | RABBITMQ_PASSWORD, DB_PASSWORD, TAILSCALE_AUTH_KEY | ✓ |
| `terraform/terraform.tfvars` | cloud credentials, db_password, ssh_public_key_path | ✓ |
| `terraform/terraform.tfstate` | live infrastructure state | ✓ |
| `/d/.ssh/k3s-config.yaml` | k3s cluster admin credentials | local only |
