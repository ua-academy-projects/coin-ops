# CoinOps — Cloud Deployment

Personal cloud deployment branch: `dev-penina-cloud`
Owner: Marta Penina (@MartaPenina)
Based on: `dev` branch of [ua-academy-projects/coin-ops](https://github.com/ua-academy-projects/coin-ops)

---

## What This Branch Does

Deploys the CoinOps application to AWS / Azure / GCP using:
- **Terraform** — provisions cloud infrastructure
- **Ansible** — configures VMs and deploys containers
- **Docker Compose** — runs services on each VM

## Application

Coin rates monitoring dashboard:
- Live BTC, ETH prices from CoinGecko
- USD/UAH rate from NBU
- Historical data charts
- Accessible at: `coinops-penina.pp.ua` (AWS, live)

---

## Architecture

```
Internet
  │
  ▼
Load Balancer  (AWS ALB / Azure LB / GCP LB)
  │
  ▼
node-03 — nginx + React UI          (public IP, secondary zone)
  │
  ├── /api/         → node-02 — Go proxy + Redis   (private, primary zone)
  │                     │
  │                     └── publishes → node-01 — RabbitMQ   (private, primary zone)
  │                                         │
  │                                         └── consumer → Managed PostgreSQL
  │
  └── /history-api/ → node-01 — History API        (private, primary zone)
                          │
                          └── reads → Managed PostgreSQL

SSH: Your machine → jump-host (public, port 9922) → node-01/02/03
```

---

## Cloud Status

| Cloud | Infrastructure | Ansible | App | URL |
|-------|---------------|---------|-----|-----|
| **AWS** | ✅ Complete | ✅ Complete | ✅ Live | coinops-penina.pp.ua |
| **Azure+AWS Hybrid** | ✅ Complete | ⏳ Pending | ⏳ Pending | — |
| **GCP** | 📝 Code ready | ⏳ Pending | ⏳ Pending | — |

---

## AWS (Complete)

| Resource | Value |
|----------|-------|
| Region | eu-central-1 (Frankfurt) |
| Jump host | 63.177.243.223 |
| ALB DNS | coinops-alb-73161503.eu-central-1.elb.amazonaws.com |
| RDS endpoint | coinops-db.cj8kme8e0kqa.eu-central-1.rds.amazonaws.com |
| State storage | S3: `devops-intern-penina-tf-state` + DynamoDB lock |

## Azure + AWS Hybrid (Infrastructure Complete ✅)

### Why Hybrid?

Azure Free account has a quota of 4 vCPU per region. The minimum available VM size is `Standard_B2s_v2` (2 vCPU). Deploying all 4 VMs would require 8 vCPU which exceeds the quota. Solution: deploy 2 VMs in Azure and 2 VMs in AWS, with PostgreSQL in Azure.

### How Hybrid Works

The `config.yaml` now supports a `cloud` field per VM:

```yaml
general:
  cloud: "hybrid"   # ← new mode: mix of Azure + AWS

vms:
  jump-host:
    cloud: "azure"  # ← Azure
  node-01:
    cloud: "aws"    # ← AWS
  node-02:
    cloud: "aws"    # ← AWS
  node-03:
    cloud: "azure"  # ← Azure
```

Each Terraform module filters VMs by their `cloud` field using `lookup(vm, "cloud", var.config.general.cloud)`. Azure modules create only Azure VMs, AWS modules create only AWS VMs.

### Azure Resources (swedencentral)

| Resource | Value |
|----------|-------|
| Account | Azure Free ($200 credit) |
| Region | swedencentral |
| Infra RG | coinops-rg (Terraform managed) |
| State RG | coinops-tfstate-rg (bootstrap managed) |
| Storage account | coinopsmpenina |
| VM size | Standard_B2s_v2 (2 vCPU) |
| jump-host public IP | 51.12.241.124 |
| LB public IP | 135.225.91.188 |
| PostgreSQL | coinops-db.coinops.postgres.database.azure.com (private) |

### AWS Resources (eu-central-1)

| Resource | Value |
|----------|-------|
| node-01 | RabbitMQ + History API (private subnet) |
| node-02 | Go proxy + Redis (private subnet) |
| VPC | 10.0.0.0/16 |

### Terraform State

State is stored in Azure Blob Storage:
- Resource group: `coinops-tfstate-rg`
- Storage account: `coinopsmpenina`
- Container: `tfstate`
- Both Azure and AWS resources are in the same state file

---

## Azure Deployment — Problems & Solutions

### Problem 1 — AuthorizationFailed on providers/read
**What:** Terraform failed on init with 403 on `Microsoft.DataLakeStore/register/action` and ~50 other providers.
**Why:** By default `azurerm` provider tries to register all ~50 known Azure services. Student SP didn't have permission for most.
**Fix:** Added `resource_provider_registrations = "none"` to provider block + upgraded azurerm to `~> 4.0`. We register only what we need manually in bootstrap.

### Problem 2 — azurerm ~> 3.0 didn't support resource_provider_registrations
**What:** `Unsupported argument` error on `resource_provider_registrations`.
**Why:** The parameter was added in azurerm 3.111+.
**Fix:** Changed `version = "~> 3.0"` to `version = "~> 4.0"` in provider.tf + ran `terraform init -upgrade`.

### Problem 3 — Contributor role disappeared
**What:** After some operations, `az role assignment list` showed only `Reader`, no `Contributor`.
**Why:** Role got detached during credential operations.
**Fix:** Manually re-assigned Contributor. Added explicit Reader assignment to bootstrap.

### Problem 4 — Student subscription: strict regional policy
**What:** `RequestDisallowedByAzure` for network resources in most regions.
**Why:** Azure student subscription has `sys.regionrestriction` policy — only 5 EU regions allowed.
**Fix:** Discovered policy using `az policy assignment list`. Created new Azure Free account with no policy restrictions.

### Problem 5 — vCPU quota too low for 4 VMs
**What:** Free account quota is 4 vCPU per region. Minimum VM size `Standard_B2s_v2` = 2 vCPU. 4 VMs × 2 vCPU = 8 vCPU > 4 quota.
**Why:** Azure Free accounts have very limited vCPU quota.
**Fix:** Hybrid deployment — 2 VMs in Azure (jump-host + node-03) + 2 VMs in AWS (node-01 + node-02). Added `cloud` field per VM in config.yaml. Each Terraform module filters VMs by their assigned cloud.

### Problem 6 — Storage account name globally taken
**What:** `StorageAccountAlreadyTaken` — `coinopspenina` already exists in student account.
**Why:** Azure storage account names are globally unique across ALL subscriptions.
**Fix:** Renamed to `coinopsmpenina`.

### Problem 7 — Resource Group chicken-and-egg
**What:** Mentor requirement: RG must be created by Terraform. But Terraform needs storage account before it runs, and storage account needs a RG.
**Fix:** Two separate RGs: `coinops-tfstate-rg` (bootstrap, storage only) and `coinops-rg` (Terraform, all infra).

### Problem 8 — data "azurerm_resource_group" fails
**What:** Modules used `data "azurerm_resource_group"` which fails because RG doesn't exist yet.
**Fix:** Replaced with `resource "azurerm_resource_group"` in azure_network. Other modules take rg_name/location from config locals.

### Problem 9 — disk_size 10GB too small
**What:** Ubuntu 24.04 in Azure requires minimum 30GB OS disk.
**Fix:** Changed `disk_size: 30` in config.yaml.

### Problem 10 — PostgreSQL ConflictingPublicNetworkAccess
**What:** Conflict between private networking and public access settings.
**Fix:** Added `public_network_access_enabled = false`.

### Problem 11 — set -e stopped bootstrap on versioning failure
**Fix:** Added `|| echo "skipping"` to versioning command.

### Problem 12 — Git Bash path conversion
**What:** Paths `/subscriptions/...` became `C:/Program Files/Git/subscriptions/...`.
**Fix:** Prefix commands with `MSYS_NO_PATHCONV=1`.

### Problem 13 — Azure API race condition (ResourceGroupNotFound / already exists)
**What:** Resources created in Azure but not recorded in Terraform state. Next apply fails with `already exists`.
**Why:** Azure eventual consistency — resource created but API not yet propagated across all datacenter nodes.
**Fix:** Re-run `terraform apply` (idempotent). Import stuck resources with `MSYS_NO_PATHCONV=1 terraform import`.

### Problem 14 — germanywestcentral: Standard_B1s and PostgreSQL unavailable
**What:** `SkuNotAvailable` for VMs and `LocationIsOfferRestricted` for PostgreSQL in germanywestcentral on Free account.
**Why:** check-regions.sh had a bug — it tested NSG creation using `coinops-tfstate-rg` (swedencentral) which gave false positives for all regions.
**Fix:** Moved to swedencentral which genuinely supports all required services.

### Problem 15 — Hybrid cloud: active_location lookup fails for "hybrid"
**What:** `local.config.locations["europe"]["hybrid"]` doesn't exist in config.yaml.
**Why:** `active_location` was designed for single-cloud mode.
**Fix:** Added fallback: `cloud == "hybrid" ? locations["europe"]["azure"] : locations["europe"][cloud]`.

### Problem 16 — aws_rds and aws_lb created in hybrid mode
**What:** After sed replacement, aws_rds and aws_lb also got `contains(["aws","hybrid"])` condition and would create in hybrid mode.
**Why:** We don't need AWS RDS (using Azure PostgreSQL) or AWS LB (using Azure LB) in hybrid mode.
**Fix:** Reverted aws_rds and aws_lb conditions back to `cloud == "aws"` only.

---

## Quick Start

### Prerequisites
- AWS CLI configured
- Azure CLI (`az`) configured and logged in
- Terraform installed
- Ansible installed
- SSH key at `~/.ssh/id_ed25519`

### Deploy Hybrid (Azure + AWS)

```bash
# 1. Bootstrap Azure state storage (run once)
cd bootstrap/azure && ./bootstrap.sh

# 2. Set config
# terraform/config.yaml → general.cloud: "hybrid"
# Set cloud per VM: jump-host/node-03 → azure, node-01/node-02 → aws

# 3. Add credentials to terraform/terraform.tfvars
# azure_subscription_id, azure_client_id, azure_client_secret, azure_tenant_id
# aws_access_key, aws_secret_key, db_password

# 4. Set Azure backend in terraform/backend.tf

# 5. Deploy
cd terraform
terraform init -reconfigure
terraform apply -auto-approve

# If "already exists" errors — import stuck resources:
# MSYS_NO_PATHCONV=1 terraform import "module.X.resource[0]" "/subscriptions/..."
```

### Check Available Azure Regions

```bash
bash bootstrap/azure/check-regions.sh
```

---

## Project Structure

```
coin-ops/
├── ansible/
│   ├── group_vars/
│   ├── roles/
│   ├── deploy.yml
│   ├── inventory              ← update IPs after terraform apply
│   └── provision.yml
├── bootstrap/
│   ├── aws/bootstrap.sh
│   ├── azure/
│   │   ├── bootstrap.sh       ← state RG + storage + SP + roles
│   │   └── check-regions.sh  ← find working Azure regions
│   └── gcp/bootstrap.sh
├── terraform/
│   ├── modules/
│   │   ├── aws_lb/
│   │   ├── aws_network/
│   │   ├── aws_rds/
│   │   ├── aws_security/
│   │   ├── aws_vm/            ← filters VMs by vm.cloud == "aws"
│   │   ├── azure_db/
│   │   ├── azure_lb/
│   │   ├── azure_network/
│   │   ├── azure_security/
│   │   ├── azure_vm/          ← filters VMs by vm.cloud == "azure"
│   │   ├── gcp_lb/
│   │   ├── gcp_network/
│   │   ├── gcp_security/
│   │   ├── gcp_sql/
│   │   └── gcp_vm/
│   ├── backend.tf             ← Azure Blob Storage backend
│   ├── config.yaml            ← cloud: "hybrid", vm-level cloud assignment
│   ├── main.tf
│   ├── outputs.tf
│   ├── provider.tf
│   └── variables.tf
└── ui-react/
```

---

## Secrets — Never Commit These

| File | Contains | Gitignored |
|------|---------|-----------|
| `.env` | RABBITMQ_PASSWORD, DB_PASSWORD, SSH_KEY_PATH | ✓ |
| `terraform/terraform.tfvars` | cloud credentials, db_password | ✓ |
| `bootstrap/gcp/key.json` | GCP service account key | ✓ |
| `terraform/terraform.tfstate` | live infrastructure state | ✓ |
