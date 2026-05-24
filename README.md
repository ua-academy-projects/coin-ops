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
- **Tailscale** — overlay VPN connecting VMs across clouds
- **Cloudflare** — DNS + HTTPS proxy

## Application

Coin rates monitoring dashboard:
- Live BTC, ETH prices from CoinGecko
- USD/UAH rate from NBU
- Historical data charts
- Accessible at: `https://coinops-penina.pp.ua` (Hybrid Azure+AWS, live ✅)

---

## Architecture

```
Internet
  │
  ▼
Cloudflare (HTTPS, coinops-penina.pp.ua)
  │
  ▼
node-03 — nginx + React UI     (Azure swedencentral, public IP 74.241.253.170)
  │
  │  [Tailscale overlay 100.x.x.x — encrypted tunnel across clouds]
  │
  ├── /api/         → node-02 — Go proxy + Redis   (AWS eu-central-1, 100.82.194.81)
  │                     │
  │                     └── publishes → node-01 — RabbitMQ + History API (AWS, 100.91.119.121)
  │                                         │
  │                                         └── AWS RDS PostgreSQL (private subnet)
  │
  └── /history-api/ → node-01 — History API (AWS eu-central-1, 100.91.119.121)

SSH: Your machine → jump-host (Azure, port 9922, 20.240.186.9) → all nodes via Tailscale
```

---

## Cloud Status

| Cloud | Infrastructure | Ansible | App | URL |
|-------|---------------|---------|-----|-----|
| **Azure+AWS Hybrid** | ✅ Complete | ✅ Complete | ✅ Live | coinops-penina.pp.ua |
| **AWS only** | ✅ Complete | ✅ Complete | ✅ Previous | — |
| **GCP** | 📝 Code ready | ⏳ Pending | ⏳ Pending | — |

---

## Hybrid Azure + AWS (Current)

### VM Distribution

| VM | Cloud | Region | Role | Tailscale IP |
|----|-------|--------|------|-------------|
| jump-host | Azure | swedencentral | SSH entry point | 100.105.243.93 |
| node-03 | Azure | swedencentral | nginx + React UI | 100.106.115.73 |
| node-01 | AWS | eu-central-1 | RabbitMQ + History API | 100.91.119.121 |
| node-02 | AWS | eu-central-1 | Go proxy + Redis | 100.82.194.81 |
| PostgreSQL RDS | AWS | eu-central-1 | Managed database | private subnet |
| Terraform state | GCP | europe-central2 | State storage | gs://devops-intern-penina-tf-state |

### Why Hybrid?

Azure for Students has a quota of 6 vCPU per region. Minimum VM size `Standard_B2s_v2` = 2 vCPU. 4 VMs × 2 vCPU = 8 vCPU exceeds quota. Solution: 2 VMs in Azure (jump-host + node-03) + 2 VMs in AWS (node-01 + node-02).

### How Hybrid Works

`config.yaml` supports a `cloud` field per VM:

```yaml
general:
  cloud: "hybrid"

vms:
  jump-host:
    cloud: "azure"
  node-01:
    cloud: "aws"
  node-02:
    cloud: "aws"
  node-03:
    cloud: "azure"
```

Each Terraform module filters VMs by `cloud` field using `lookup(vm, "cloud", var.config.general.cloud)`.

---

## Tailscale — Cross-Cloud Networking

### Problem

Azure VNet and AWS VPC are isolated networks — they cannot communicate directly. Without a solution, the Azure jump-host cannot reach AWS nodes, and Ansible cannot provision them.

### Solution: Tailscale Overlay Network

Tailscale creates an encrypted overlay network on top of existing cloud networks. Each VM gets a `100.x.x.x` IP and can communicate with all other VMs regardless of which cloud they are in.

```
Azure VNet (10.0.x.x)              AWS VPC (10.0.x.x)
  jump-host  ←——— Tailscale ———→  node-01
  100.105.243.93   encrypted        100.91.119.121
  
  node-03    ←——— tunnel   ———→  node-02
  100.106.115.73   over internet    100.82.194.81
```

### Current Setup (All Nodes)

Tailscale is installed on all nodes via Ansible role. Each VM joins the tailnet with the same auth key.

> ⚠️ **TODO (mentor feedback):** The correct approach is to install Tailscale only on jump-host as a **subnet router** — it advertises the internal cloud subnets to the tailnet, so other VMs don't need Tailscale installed individually. This reduces attack surface and is closer to production practice.
>
> Current workaround: Tailscale installed on all nodes directly.

### Tailscale Files

| File | Purpose |
|------|---------|
| `ansible/roles/tailscale/tasks/main.yml` | Installs Tailscale, starts `tailscaled`, runs `tailscale up` |
| `ansible/roles/tailscale/defaults/main.yml` | Default vars: `tailscale_auth_key`, `tailscale_hostname` |
| `ansible/provision.yml` | Calls tailscale role on `hosts: all` |
| `.env` on jump-host | Contains `TAILSCALE_AUTH_KEY=tskey-auth-xxxxx` |

### Tailscale Dashboard

Machines visible in tailnet (`login.tailscale.com/admin/machines`):
- AWS nodes appear as `ip-10-0-1-xxx` — AWS auto-generates hostname from private IP
- Azure nodes appear as `jump-host`, `node-03` — hostname taken from VM name in Terraform

---

## Azure Resources (swedencentral)

| Resource | Value |
|----------|-------|
| Account | Azure for Students |
| Subscription | 387c88f6-124c-413f-936b-75b578dbabc9 |
| Allowed regions | spaincentral, francecentral, germanywestcentral, swedencentral, italynorth |
| Infra RG | coinops-rg (Terraform managed) |
| VM size | Standard_B2s_v2 (2 vCPU) |
| jump-host public IP | 20.240.186.9 |
| node-03 public IP | 74.241.253.170 |
| Azure LB | 172.160.228.124 (configured, not used — instance IP used instead) |

## AWS Resources (eu-central-1)

| Resource | Value |
|----------|-------|
| node-01 | RabbitMQ + History API (public subnet, public IP — temp) |
| node-02 | Go proxy + Redis (public subnet, public IP — temp) |
| RDS PostgreSQL | private subnet, db.t3.micro, free tier |
| VPC | 10.0.0.0/16 |

> ⚠️ **TODO:** node-01/02 still have public IPs. Once Tailscale subnet router is configured on jump-host, public IPs can be removed and nodes moved to private subnet.

## Terraform State (GCP)

| Resource | Value |
|----------|-------|
| Bucket | `devops-intern-penina-tf-state` |
| Prefix | `coinops-cloud/state` |
| Backend | `gcs` in `backend.tf` |

---

## Quick Start

### Prerequisites

- AWS CLI configured
- Azure CLI (`az`) logged in as `marta.penina.pp.2022@lpnu.ua` (Students account)
- GCP CLI (`gcloud`) configured as `marta.penina.academic@gmail.com`
- Terraform installed
- SSH key at `/d/.ssh/id_ed25519`
- Tailscale account with reusable auth key

### Deploy Hybrid (Azure + AWS)

```bash
# 1. Bootstrap Azure SP (run once per Azure account)
cd bootstrap/azure && bash bootstrap.sh
# Save client_id, client_secret, tenant_id from output

# 2. Set credentials in terraform/terraform.tfvars
# azure_subscription_id, azure_client_id, azure_client_secret, azure_tenant_id
# aws_access_key, aws_secret_key, db_password

# 3. GCP backend is active in terraform/backend.tf (gcs section uncommented)

# 4. Init
cd terraform
terraform init -reconfigure

# 5. ALWAYS check plan before apply — changing public_ip causes VM recreation
terraform plan

# 6. Apply
terraform apply -auto-approve

# 7. On jump-host: install Ansible and clone repo
ssh -A -p 9922 marta_ops@<jump-host-ip>
sudo apt install -y ansible git
git clone https://github.com/ua-academy-projects/coin-ops.git
cd coin-ops && git checkout dev-penina-cloud

# 8. Set .env on jump-host (copy from local or create manually)
# Required: RABBITMQ_PASSWORD, DB_PASSWORD, SSH_KEY_PATH, TAILSCALE_AUTH_KEY

# 9. Update ansible/inventory with current IPs

# 10. Provision (Docker + Tailscale on all nodes)
source .env
ansible-playbook -i ansible/inventory ansible/provision.yml

# 11. If tailscale up was skipped — run manually on each node
ssh -p 9922 marta_ops@<node-ip> "sudo tailscale up --authkey=$TAILSCALE_AUTH_KEY"

# 12. Update inventory to Tailscale IPs (100.x.x.x)
# Run: tailscale status on jump-host to get IPs

# 13. Deploy app
ansible-playbook -i ansible/inventory ansible/deploy.yml

# 14. Destroy when done to save credits
terraform destroy -auto-approve
```

---

## Problems & Solutions

### Problem 1 — Azure Free Trial expired in 2-3 days
**What:** $200 credit gone, services paused.
**Why:** 30-day time limit hit (not spending limit). Only $6.85 was actually spent.
**Fix:** Switched to Azure for Students account — $100 credit, no 30-day limit, no card required.

### Problem 2 — Azure for Students has regional policy restrictions
**What:** Only 5 EU regions allowed: spaincentral, francecentral, germanywestcentral, swedencentral, italynorth.
**Fix:** Used `az policy assignment list` to discover allowed regions. Deployed to swedencentral.

### Problem 3 — AWS node-01/02 unreachable from Azure jump-host
**What:** `internal-sg` only allowed SSH from `jump-host-sg` (AWS SG reference) — doesn't work cross-cloud.
**Fix:** Added `dynamic "ingress"` block in `aws_security/main.tf` — in hybrid mode, port 9922 allowed from `0.0.0.0/0`.

### Problem 4 — Tailscale `tailscale up` skipped on second provision
**What:** Task used `creates: /var/lib/tailscale/tailscaled.state` — file existed, command skipped. VMs showed `Logged out`.
**Fix:** Run `tailscale up` manually via SSH after provision.

### Problem 5 — node-03 got internal-nsg instead of web-nsg
**What:** node-03 had tags `["internal", "ui", "web"]`. Azure allows only one NSG per NIC. `internal-nsg` was applied last, blocking port 80.
**Fix:** Removed `internal` tag from node-03. Only `web-nsg` now applied.

### Problem 6 — NIC state drift after CLI changes
**What:** Used `az network nic update` directly — created drift between Terraform state and Azure. Subsequent apply failed.
**Lesson:** Never modify Terraform-managed resources via CLI.
**Fix:** `terraform state rm` + `terraform import` to re-sync.

### Problem 7 — Terraform state desync for AWS VMs
**What:** After multiple destroy/recreate cycles, state held old terminated instance IDs.
**Fix:** `terraform state rm` for affected VMs, then `terraform apply`.

### Problem 8 — Changing public_ip causes VM recreation
**What:** Changing `public_ip: true → false` moves VM to different subnet — AWS requires destroy + recreate.
**Why:** Subnet cannot be changed on running EC2 instance.
**Lesson:** Always run `terraform plan` first. Any subnet change = VM recreation = need for new provision + deploy.

### Problem 9 — Git Bash path conversion
**What:** Paths `/subscriptions/...` became `C:/Program Files/Git/subscriptions/...`.
**Fix:** Prefix commands with `MSYS_NO_PATHCONV=1`.

---

## Project Structure

```
coin-ops/
├── ansible/
│   ├── roles/
│   │   ├── common/       ← base packages, UFW firewall
│   │   ├── docker/       ← Docker + Compose
│   │   ├── tailscale/    ← Tailscale VPN overlay (tasks/, defaults/)
│   │   ├── history/      ← History service deploy
│   │   ├── proxy/        ← Proxy service deploy
│   │   └── ui/           ← UI + nginx deploy
│   ├── deploy.yml
│   ├── inventory         ← Tailscale IPs (100.x.x.x) after provision
│   └── provision.yml
├── bootstrap/
│   ├── aws/bootstrap.sh
│   └── azure/
│       ├── bootstrap.sh       ← SP creation + role assignments
│       └── check-regions.sh   ← find allowed Azure regions + quota
├── terraform/
│   ├── modules/
│   │   ├── aws_network/   ├── aws_security/  ├── aws_vm/
│   │   ├── aws_rds/       ├── aws_lb/
│   │   ├── azure_network/ ├── azure_security/ ├── azure_vm/
│   │   ├── azure_db/      ├── azure_lb/
│   │   └── gcp_*/         ← GCP modules (code ready, not deployed yet)
│   ├── backend.tf    ← GCP backend (gcs bucket)
│   ├── config.yaml   ← hybrid mode, per-VM cloud field, database: "aws"
│   ├── main.tf
│   ├── outputs.tf
│   ├── provider.tf
│   └── variables.tf
└── ui-react/
```

---

## Secrets — Never Commit

| File | Contains | Gitignored |
|------|---------|-----------|
| `.env` | RABBITMQ_PASSWORD, DB_PASSWORD, TAILSCALE_AUTH_KEY | ✓ |
| `terraform/terraform.tfvars` | cloud credentials, db_password | ✓ |
| `terraform/terraform.tfstate` | live infrastructure state | ✓ |
