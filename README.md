# CoinOps — Cloud Deployment

Personal cloud deployment branch: `dev-penina-cloud`
Owner: Marta Penina (@MartaPenina)
Based on: `dev` branch of [ua-academy-projects/coin-ops](https://github.com/ua-academy-projects/coin-ops)

---

## What This Branch Does

Deploys the CoinOps application to AWS (and GCP) using:
- **Terraform** — provisions cloud infrastructure
- **Ansible** — configures VMs and deploys containers
- **Docker Compose** — runs services on each VM

## Application

Coin rates monitoring dashboard:
- Live BTC, ETH prices from CoinGecko
- USD/UAH rate from NBU
- Historical data charts
- Accessible at: `coinops-penina.pp.ua`

---

## Architecture

```
Internet
  │
  ▼
AWS ALB (Load Balancer)
  │
  ▼
node-03 — nginx + React UI          (public IP, zone b)
  │
  ├── /api/         → node-02 — Go proxy + Redis   (private, zone a)
  │                     │
  │                     └── publishes → node-01 — RabbitMQ   (private, zone a)
  │                                         │
  │                                         └── consumer → AWS RDS PostgreSQL
  │
  └── /history-api/ → node-01 — History API        (private, zone a)
                          │
                          └── reads → AWS RDS PostgreSQL

SSH: Your machine → jump-host (public, port 9922) → node-01/02/03
```

---

## Cloud Infrastructure

| Resource | AWS | GCP |
|----------|-----|-----|
| VMs | EC2 t3.micro | e2-micro |
| Database | RDS PostgreSQL | CloudSQL (planned) |
| Load Balancer | ALB | Cloud LB (planned) |
| State storage | S3 bucket | GCS bucket |
| Region | eu-central-1 (Frankfurt) | europe-central2 (Warsaw) |

Switch between clouds by changing `general.cloud` in `terraform/config.yaml`.

---

## Quick Start

### Prerequisites
- AWS CLI configured with access key + secret key
- GCP CLI (`gcloud`) configured
- Terraform installed
- Ansible installed
- SSH key at `~/.ssh/id_ed25519`

### First Time Setup

```bash
# 1. Clone and switch branch
git clone https://github.com/ua-academy-projects/coin-ops
git checkout dev-penina-cloud

# 2. Copy and fill secrets
cp .env.example .env
# edit .env — add RABBITMQ_PASSWORD, DB_PASSWORD, SSH_KEY_PATH

# 3. Bootstrap cloud state storage (run once per cloud)
cd bootstrap/aws && ./bootstrap.sh   # creates S3 bucket + DynamoDB
cd bootstrap/gcp && ./bootstrap.sh   # creates GCS bucket + service account
```

### Deploy to AWS

```bash
# 1. Load environment
source .env

# 2. Make sure config.yaml has cloud: "aws"
# terraform/config.yaml → general.cloud: "aws"

# 3. Switch backend.tf to S3, then init
# uncomment S3 backend in terraform/backend.tf
terraform -chdir=terraform init -migrate-state

# 4. Create infrastructure
terraform -chdir=terraform apply

# 5. Get outputs and update Ansible inventory
terraform -chdir=terraform output
# copy IPs into ansible/inventory
# copy rds_endpoint into ansible/group_vars/all/main.yml

# 6. Provision VMs (install Docker)
ansible-playbook -i ansible/inventory ansible/provision.yml

# 7. Deploy application
IMAGE_TAG=shabat-latest ansible-playbook -i ansible/inventory ansible/deploy.yml
```

### After Every terraform destroy + apply
```bash
# Update these two files with new values from terraform output:
ansible/inventory                        # new VM IPs
ansible/group_vars/all/main.yml          # new rds_endpoint
```

---

## Project Structure

```
coin-ops/
├── ansible/                 ← provisioning and deployment
│   ├── group_vars/          ← variables per node group
│   ├── roles/               ← common, docker, history, proxy, ui
│   ├── deploy.yml           ← deploys containers
│   ├── inventory            ← VM IPs (update after terraform apply)
│   └── provision.yml        ← installs Docker
├── bootstrap/
│   ├── aws/bootstrap.sh     ← creates S3 bucket + DynamoDB lock
│   ├── azure/               ← planned
│   └── gcp/bootstrap.sh     ← creates GCS bucket + service account
├── deploy/
│   └── compose/             ← per-node Docker Compose templates
│       ├── node-01.compose.yaml
│       ├── node-02.compose.yaml
│       └── node-03.compose.yaml
├── docs/                    ← architecture, deployment docs
├── history/                 ← Python FastAPI + RabbitMQ consumer
├── proxy/                   ← Go proxy service
├── runtime/                 ← PostgreSQL runtime mode (alternative)
├── smoke/                   ← end-to-end smoke tests
├── terraform/               ← infrastructure as code
│   ├── modules/
│   │   ├── aws_lb/          ← Application Load Balancer
│   │   ├── aws_network/     ← VPC, subnets, IGW, NAT
│   │   ├── aws_rds/         ← managed PostgreSQL
│   │   ├── aws_security/    ← security groups
│   │   ├── aws_vm/          ← EC2 instances
│   │   ├── gcp_network/     ← VPC, firewall rules
│   │   ├── gcp_security/    ← firewall rules
│   │   └── gcp_vm/          ← compute instances
│   ├── backend.tf           ← state storage (S3 or GCS)
│   ├── config.yaml          ← all infrastructure decisions
│   ├── main.tf              ← calls all modules
│   ├── outputs.tf           ← prints IPs and DNS after apply
│   ├── provider.tf          ← AWS + GCP providers
│   └── variables.tf         ← secret variable declarations
├── tests/                   ← unit + integration tests
└── ui-react/                ← React frontend
```

---

## Secrets — Never Commit These

| File | Contains | Gitignored |
|------|---------|-----------|
| `.env` | RABBITMQ_PASSWORD, DB_PASSWORD, SSH_KEY_PATH | ✓ |
| `terraform/terraform.tfvars` | aws_access_key, aws_secret_key, db_password | ✓ |
| `bootstrap/gcp/key.json` | GCP service account credentials | ✓ |
| `terraform/terraform.tfstate` | live infrastructure state | ✓ |

---

## Runtime Mode

This branch uses `RUNTIME_BACKEND=external`:
```
Proxy → RabbitMQ → history-consumer → PostgreSQL
Proxy → Redis (cache)
```

The PostgreSQL runtime mode (`RUNTIME_BACKEND=postgres`) exists in `runtime/`
but is not the default on this branch.

---

## Container Images

Built by GitHub Actions, pushed to GHCR:

| Service | Image |
|---------|-------|
| UI | `ghcr.io/ua-academy-projects/coin-ops-ui` |
| Proxy | `ghcr.io/ua-academy-projects/coin-ops-proxy` |
| History API | `ghcr.io/ua-academy-projects/coin-ops-history-api` |
| History Consumer | `ghcr.io/ua-academy-projects/coin-ops-history-consumer` |

Tags: `shabat-latest` (default), `dev-latest`, `vX.Y.Z`

---

## Local Development

```bash
# Run everything locally with Docker Compose
cp .env.compose.example .env
docker compose up --build

# Open at http://localhost:5000
```

---

## Known Issues

- GCP load balancer and CloudSQL modules not yet implemented
- Ansible inventory IPs must be updated manually after every redeploy
- RDS endpoint hardcoded in group_vars, must update after redeploy
- Azure bootstrap folder is empty (planned for future)

---

## Documentation

| Doc | Description |
|-----|-------------|
| `08-deploy-coinops-cloud.md` | Task description and deployment steps |
| `docs/architecture.md` | System architecture |
| `docs/deployment.md` | Deployment guide |
| `docs/terraform-guide.md` | Terraform usage |
| `CLAUDE.md` | AI assistant context |
| `CONTRIBUTING.md` | Team contribution rules |
