# CoinOps — Cloud Deployment

Personal cloud deployment branch: `dev-penina-cloud`
Owner: Marta Penina (@MartaPenina)
Based on: `dev` branch of [ua-academy-projects/coin-ops](https://github.com/ua-academy-projects/coin-ops)

---

## What This Branch Does

Deploys the CoinOps application to AWS + Azure (hybrid multi-cloud) using:
- **Terraform** — provisions cloud infrastructure across Azure + AWS
- **Ansible** — configures VMs and deploys containers
- **Docker Compose** — runs services on each VM
- **Tailscale** — overlay VPN with subnet router pattern connecting VMs across clouds
- **Cloudflare** — DNS + HTTPS proxy

## Application

Coin rates monitoring dashboard:
- Live BTC, ETH prices from CoinGecko
- USD/UAH rate from NBU
- Historical data charts
- Accessible at: `https://coinops-softserve-penina.pp.ua` (Hybrid Azure+AWS, live ✅)

---

## Architecture

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

---

## Cloud Status

| Cloud | Infrastructure | Ansible | App | URL |
|-------|---------------|---------|-----|-----|
| **Azure+AWS Hybrid** | ✅ Complete | ✅ Complete | ✅ Live | coinops-softserve-penina.pp.ua |
| **GCP** | 📝 Planned | ⏳ Pending | ⏳ Pending | Task 2 |

---

## Hybrid Azure + AWS (Current)

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

### Why Hybrid?

Azure Free account quota: 4 vCPU in swedencentral. `Standard_B2s_v2` = 2 vCPU each. Maximum 2 Azure VMs = 4 vCPU. Solution: jump-host moved to AWS, leaving gateway-azure + node-03 in Azure = 4 vCPU exactly.

### Tailscale Subnet Router Pattern

See [docs/tailscale-subnet-router.md](docs/tailscale-subnet-router.md) for full explanation.

Summary: instead of installing Tailscale on every VM, one dedicated gateway VM per network acts as subnet router. It advertises its entire subnet to the Tailscale network. Other VMs need no Tailscale installed — they are reachable through the gateway's route.

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

## Quick Start

### Prerequisites

- AWS CLI configured
- Azure CLI (`az`) logged in to Azure subscription 1 (`309b8392...`)
- GCP CLI (`gcloud`) configured as `marta.penina.academic@gmail.com`
- Terraform installed
- SSH key at `/d/.ssh/id_ed25519_devops`
- Tailscale account with reusable auth key

### Deploy Hybrid (Azure + AWS)

```bash
# 1. Set credentials in terraform/terraform.tfvars
# azure_subscription_id, azure_client_id, azure_client_secret, azure_tenant_id
# aws_access_key, aws_secret_key, db_password, tailscale_auth_key
# ssh_public_key_path = "D:/.ssh/id_ed25519_devops.pub"

# 2. GCP backend active in terraform/backend.tf
cd terraform
terraform init -reconfigure

# 3. Always check plan first
terraform plan

# 4. Apply
terraform apply -auto-approve

# 5. SSH to jump-host
eval $(ssh-agent -s)
ssh-add /d/.ssh/id_ed25519_devops
ssh -A -p 9922 marta_ops@3.70.205.142

# 6. On jump-host: clone repo
git clone https://github.com/ua-academy-projects/coin-ops.git
cd coin-ops && git checkout dev-penina-cloud

# 7. Copy .env from local
# (from local machine) scp -P 9922 /d/DevOps_internship/coin-ops/.env marta_ops@3.70.205.142:~/coin-ops/.env

# 8. Provision (all nodes except node-03 first)
source .env
ansible-playbook -i ansible/inventory ansible/provision.yml --limit 'all:!node-03'

# 9. Fix Tailscale CIDRs on gateways
ssh -p 9922 marta_ops@10.0.1.145 "sudo tailscale up --accept-routes --advertise-routes=10.0.1.0/24,10.0.2.0/24 --hostname=gateway-aws"
ssh -p 9922 marta_ops@135.225.57.231 "sudo tailscale up --accept-routes --advertise-routes=10.0.4.0/24 --hostname=gateway-azure"

# 10. Approve routes in Tailscale admin panel
# https://login.tailscale.com/admin/machines
# gateway-aws  → enable 10.0.1.0/24 and 10.0.2.0/24
# gateway-azure → enable 10.0.4.0/24

# 11. Provision node-03 (now reachable via Tailscale)
ansible-playbook -i ansible/inventory ansible/provision.yml --limit node-03

# 12. Deploy app
ansible-playbook -i ansible/inventory ansible/deploy.yml

# 13. Add DNS in Cloudflare
# A record: coinops-softserve-penina.pp.ua → 20.91.139.85 (Proxied)

# 14. Destroy when done to save credits
terraform destroy -auto-approve
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

[all:vars]
ansible_user=marta_ops
ansible_port=9922
ansible_ssh_private_key_file=~/.ssh/id_ed25519
ansible_ssh_common_args=-o StrictHostKeyChecking=no
```

---

## Problems & Solutions

### Problem 1 — Azure vCPU quota limit (4 vCPU in swedencentral)
**What:** 3 Azure VMs needed 6 vCPU, quota only 4.
**Fix:** Moved jump-host to AWS (t3.micro). Azure now has only gateway-azure + node-03 = 4 vCPU.

### Problem 2 — Azure public IP limit (3 per subscription)
**What:** jump-host + gateway-azure + node-03 + LB = 4 IPs needed.
**Fix:** node-03 set to `public_ip: false` — sits behind LB. LB gets the public IP instead.

### Problem 3 — Tailscale `creates:` idempotency bug
**What:** Task used `creates: /var/lib/tailscale/tailscaled.state` — file existed after first run, command always skipped.
**Fix:** Replaced with `register/changed_when` pattern.

### Problem 4 — Both gateways advertising same CIDR 10.0.0.0/16
**What:** Tailscale got confused which gateway owns which subnet.
**Fix:** Split into specific CIDRs: gateway-aws advertises `10.0.1.0/24,10.0.2.0/24`, gateway-azure advertises `10.0.4.0/24`.

### Problem 5 — node-03 unreachable via ProxyJump through jump-host
**What:** jump-host (AWS) cannot reach 10.0.4.x (Azure) — no Tailscale on jump-host.
**Fix:** node-03 uses ProxyJump through gateway-aws which has Tailscale route to Azure.

### Problem 6 — `terraform.tfstate` accidentally committed
**What:** Local state file committed to git — contains sensitive data.
**Fix:** Added to `.gitignore`. Deleted local file. GCP backend is the source of truth.

---

## Secrets — Never Commit

| File | Contains | Gitignored |
|------|---------|-----------|
| `.env` | RABBITMQ_PASSWORD, DB_PASSWORD, TAILSCALE_AUTH_KEY | ✓ |
| `terraform/terraform.tfvars` | cloud credentials, db_password, ssh_public_key_path | ✓ |
| `terraform/terraform.tfstate` | live infrastructure state | ✓ |
