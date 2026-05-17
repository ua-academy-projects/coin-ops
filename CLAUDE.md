# CLAUDE.md

Guidance for Claude when working in this repository.

## Branch Context
`dev-penina-cloud` — personal cloud deployment branch off `dev`.
Owner: Marta Penina (@MartaPenina)
Cloud: AWS (primary), GCP (in progress), Azure (planned)
Runtime: `external` (RabbitMQ + Redis)

## Architecture

| VM | Role | Services | IP type |
|----|------|---------|---------|
| jump-host | SSH gateway | none | public |
| node-01 | History + Queue | RabbitMQ, history-consumer, history-api | private |
| node-02 | Proxy + Cache | Go proxy, Redis | private |
| node-03 | Frontend | nginx, React SPA | public |
| AWS RDS | Database | PostgreSQL (managed) | private endpoint |

SSH access: always through jump-host on port 9922 as marta_ops.

## Data Flow

```
Browser
  → ALB (AWS Load Balancer)
  → nginx on node-03:80
  → /api/ → Go proxy on node-02:8080
      → checks Redis cache (localhost:6379)
      → if miss: fetches CoinGecko + NBU APIs
      → publishes to RabbitMQ on node-01:5672
      → returns data to browser
  → /history-api/ → History API on node-01:8000
      → reads from AWS RDS PostgreSQL
      → returns historical records to browser

Background:
  RabbitMQ → history-consumer → AWS RDS PostgreSQL
```

## Infrastructure Stack

### Terraform (`terraform/`)
Single codebase for AWS and GCP.
Switch cloud: change `general.cloud` in `config.yaml`.
State: GCS bucket (GCP) or S3 bucket (AWS) — see backend.tf.

**AWS modules:**
- `aws_network` — VPC, 4 subnets, IGW, NAT gateway, route tables
- `aws_security` — security groups (jump_host, internal, web, rds)
- `aws_vm` — EC2 instances (jump-host, node-01, node-02, node-03)
- `aws_lb` — Application Load Balancer, target group, listener
- `aws_rds` — managed PostgreSQL database

**GCP modules:**
- `gcp_network` — VPC, subnet, firewall rules
- `gcp_security` — firewall rules
- `gcp_vm` — compute instances
- `gcp_lb` — ⚠️ MISSING, needs implementation
- `gcp_sql` — ⚠️ MISSING, needs implementation

### Ansible (`ansible/`)
- `provision.yml` — installs Docker + system packages on all VMs
- `deploy.yml` — renders Jinja2 compose templates, pulls GHCR images, starts containers
- `inventory` — VM IPs (must update manually after terraform apply)
- `group_vars/all/main.yml` — shared variables for all nodes
- `roles/common/` — base packages, UFW firewall
- `roles/docker/` — Docker Engine installation
- `roles/history/` — deploys node-01 (RabbitMQ + history services)
- `roles/proxy/` — deploys node-02 (Go proxy + Redis)
- `roles/ui/` — deploys node-03 (nginx + React)

### Docker Compose (`deploy/compose/`)
Per-node Jinja2 templates rendered by Ansible:
- `node-01.compose.yaml` — RabbitMQ, history-consumer, history-api
- `node-02.compose.yaml` — Go proxy, Redis
- `node-03.compose.yaml` — nginx + React UI

Uses pre-built GHCR images — never builds from source on VMs.
Default image tag: `shabat-latest`

## Bootstrap (run once per cloud)

```bash
# GCP
cd bootstrap/gcp
./bootstrap.sh
export GOOGLE_APPLICATION_CREDENTIALS=$(pwd)/key.json

# AWS
cd bootstrap/aws
./bootstrap.sh
# creates S3 bucket + DynamoDB lock table
```

## Deploy Workflow

```bash
# 1. Load secrets
source .env

# 2. Provision infrastructure
terraform -chdir=terraform apply

# 3. Update inventory with new IPs from terraform output
terraform -chdir=terraform output
# edit ansible/inventory with new IPs
# edit ansible/group_vars/all/main.yml rds_endpoint with new RDS endpoint

# 4. Install Docker on VMs
ansible-playbook -i ansible/inventory ansible/provision.yml

# 5. Deploy app containers
IMAGE_TAG=shabat-latest ansible-playbook -i ansible/inventory ansible/deploy.yml
```

## After terraform destroy + apply
These values change and must be updated manually:
- `ansible/inventory` — all VM IPs
- `ansible/group_vars/all/main.yml` — `rds_endpoint`

## Key Variables (`ansible/group_vars/all/main.yml`)

| Variable | Value | Meaning |
|----------|-------|---------|
| `use_rds` | `true` | uses AWS RDS, no local PostgreSQL container |
| `runtime_backend` | `external` | uses RabbitMQ + Redis |
| `tls_mode` | `off` | no TLS on node-03, ALB handles HTTPS |
| `image_tag` | `shabat-latest` | override with IMAGE_TAG env var |
| `proxy_port` | `8080` | Go proxy port |
| `history_port` | `8000` | History API port |

## Secrets
Never committed to Git. Stored in:
- `.env` — RABBITMQ_PASSWORD, DB_PASSWORD, SSH_KEY_PATH, RUNTIME_BACKEND
- `terraform/terraform.tfvars` — aws_access_key, aws_secret_key, db_password
- `bootstrap/gcp/key.json` — GCP service account (gitignored)
- `bootstrap/aws/` — no key file, uses AWS CLI credentials

## Known Issues (being fixed)
- GCP missing `gcp_lb` and `gcp_sql` modules
- `ansible/inventory` IPs must be updated manually after every redeploy
- `rds_endpoint` hardcoded in group_vars, must update after redeploy
- `backend.tf` needs migration from local to remote backend (S3 or GCS)
