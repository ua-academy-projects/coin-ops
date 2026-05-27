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
- **Helm** — installs Kubernetes apps (cert-manager, Headlamp, Homepage, CoinOps)
- **cert-manager** — automatic TLS certificates via Let's Encrypt
- **Cloudflare** — DNS management
- **GCP Regional NLB** — pass-through Network Load Balancer for k3s cluster

## Application

Coin rates monitoring dashboard:
- Live BTC, ETH prices from CoinGecko
- USD/UAH rate from NBU
- Historical data charts
- Hybrid app: `https://coinops-softserve-penina.pp.ua` ✅
- k3s CoinOps: `https://coinops-softserve-penina.pp.ua` ✅
- k3s Homepage: `https://k3s.coinops-softserve-penina.pp.ua` ✅
- k3s Headlamp: `kubectl port-forward -n headlamp svc/headlamp 8080:80` → `localhost:8080`

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

### GCP k3s Cluster (Task 2 + Task 3 + Task 4)

```
Internet
  │
  ▼
Cloudflare DNS only (grey cloud — no proxy)
  │
  ▼
GCP Regional NLB 34.116.135.79 (pass-through — forwards TCP packets unchanged)
  │
  ├── port 80  → k3s nodes → Traefik → HTTP routes
  └── port 443 → k3s nodes → Traefik → HTTPS routes (TLS terminated by Traefik)
                                  │
                        ┌─────────┴──────────┐──────────────────┐
                        ▼                    ▼                  ▼
              coinops-frontend          homepage           headlamp
              (coinops-softserve-    (k3s.coinops-      (port-forward only)
               penina.pp.ua)          softserve-
                                       penina.pp.ua)

GCP k3s Cluster (europe-central2):
  k3s-server-1  control plane + worker  34.116.142.103 (public) / 10.0.1.2 (private)
  k3s-server-2  control plane + worker  10.0.1.4 (private)
  k3s-server-3  control plane + worker  10.0.1.3 (private, zone-b)

Namespaces:
  coinops-queue     rabbitmq, redis
  coinops-app       proxy, history-api, history-consumer, schema-init Job
  coinops-frontend  ui + Ingress
  homepage          Homepage dashboard + Ingress
  headlamp          Headlamp UI (no public Ingress)
  cert-manager      cert-manager + Let's Encrypt ClusterIssuer

Database:
  CloudSQL PostgreSQL (GCP managed, private IP 10.0.1.3, accessed via VPC peering)
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

---

## GCP k3s Cluster (Task 2 + Task 3 + Task 4)

### VM Distribution

| VM | Zone | Role | Public IP | Private IP |
|----|------|------|-----------|------------|
| k3s-server-1 | europe-central2-a | control plane + worker | 34.116.142.103 | 10.0.1.2 |
| k3s-server-2 | europe-central2-a | control plane + worker | — | 10.0.1.4 |
| k3s-server-3 | europe-central2-b | control plane + worker | — | 10.0.1.3 |
| CloudSQL | europe-central2 | PostgreSQL managed DB | — | 10.113.0.3 |
| Regional NLB | europe-central2 | Pass-through LB | 34.116.135.79 | — |

### Ansible Roles

| Role | Purpose |
|------|---------|
| `common` | UFW firewall, apt packages, timezone |
| `k3s_prereqs` | curl, Helm, pip3, python kubernetes library |
| `k3s_server_bootstrap` | initializes cluster on node-1, sets TLS SAN |
| `k3s_server_join` | joins node-2 and node-3 to cluster |
| `k3s_postcheck` | verifies all nodes Ready, downloads kubeconfig |
| `cert_manager` | installs cert-manager + Let's Encrypt ClusterIssuer |
| `k3s_headlamp` | installs Headlamp UI (no public Ingress — port-forward only) |
| `k3s_homepage` | installs Homepage dashboard + Ingress + TLS |
| `k3s_coinops` | deploys full CoinOps stack — namespaces, secrets, queue, app, frontend |

### Playbooks

```bash
# Bootstrap k3s cluster (run once)
ansible-playbook -i ansible/inventory ansible/k3s-cluster.yml

# Install all apps (cert-manager, Headlamp, Homepage, CoinOps)
ansible-playbook -i ansible/inventory ansible/k3s-apps.yml
```

### kubectl Access

```bash
# Copy kubeconfig from k3s-server-1
scp -P 9922 marta_ops@34.116.142.103:/tmp/k3s-config.yaml /d/.ssh/k3s-config.yaml

export KUBECONFIG=/d/.ssh/k3s-config.yaml
kubectl get nodes
kubectl get pods -A
```

### Headlamp Access (port-forward only — not public by design)

```bash
export KUBECONFIG=/d/.ssh/k3s-config.yaml
kubectl port-forward -n headlamp svc/headlamp 8080:80
# Open: http://localhost:8080
# Token: kubectl create token headlamp-admin -n headlamp
```

---

## Quick Start — GCP k3s

```bash
# 1. Set GCP credentials
export GOOGLE_APPLICATION_CREDENTIALS=/path/to/key.json
source .env  # loads CLOUDSQL_IP, DB_PASSWORD, RABBITMQ_PASSWORD, GHCR_TOKEN etc.

# 2. Provision infrastructure
cd terraform
terraform init -reconfigure
terraform apply -auto-approve

# 3. SSH to k3s-server-1
eval $(ssh-agent)
ssh-add /d/.ssh/id_ed25519_devops
ssh -A -p 9922 marta_ops@34.116.142.103

# 4. On k3s-server-1: clone repo, install k3s
cd coin-ops
git pull origin dev-penina-cloud
source .env
ansible-galaxy install -r ansible/requirements.yml
ansible-playbook -i ansible/inventory ansible/k3s-cluster.yml

# 5. Copy SSH key for Ansible ProxyJump to private nodes
# From local machine:
scp -P 9922 /d/.ssh/id_ed25519_devops marta_ops@34.116.142.103:~/.ssh/id_ed25519
chmod 600 ~/.ssh/id_ed25519

# 6. Deploy all apps
ansible-playbook -i ansible/inventory ansible/k3s-apps.yml

# 7. Get kubeconfig locally
scp -P 9922 marta_ops@34.116.142.103:/tmp/k3s-config.yaml /d/.ssh/k3s-config.yaml
```

---

## Problems & Solutions

### Task 4 — CoinOps on k3s

**Problem 1 — GCP Global LB TCP proxy did not pass Host header**
Global TCP proxy forwarded raw TCP bytes. Traefik uses host-based routing and could not determine the domain → returned 404 for all HTTPS requests.
Fix: replaced Global LB with Regional Network Load Balancer (pass-through mode). Regional NLB forwards TCP packets unchanged → Traefik receives original TLS connection with correct Host header.

**Problem 2 — Health check returned 404, backends UNHEALTHY**
HTTP health check sent `GET /health` without Host header → Traefik returned 404 → GCP marked all backends UNHEALTHY → 502 for all requests.
Fix: TCP health check on port 80. TCP check verifies port is open without requiring HTTP response. Standard practice for Ingress controllers behind LB.

**Problem 3 — cert-manager ACME solver Ingress had no IngressClass**
cert-manager created solver Ingress with `class: <none>` → Traefik ignored it → ACME HTTP challenge returned 502.
Fix: `ingressClassName: traefik` in ClusterIssuer solver config (replaces deprecated `class:` field for k8s 1.18+).

**Problem 4 — CloudSQL IP not available on k3s-server-1**
Playbook tried to run `terraform output` on jump-host where Terraform is not installed.
Fix: `CLOUDSQL_IP` env variable loaded from `.env` via `lookup('env', 'CLOUDSQL_IP')`. Value set dynamically: `export CLOUDSQL_IP=$(terraform output -raw gcp_db_endpoint)`.

**Problem 5 — Regional NLB requires regional health check**
Global health check resource (`google_compute_health_check`) rejected by regional backend service.
Fix: replaced with `google_compute_region_health_check` in the same region as the LB.

---

## Secrets — Never Commit

| File | Contains | Gitignored |
|------|---------|-----------|
| `.env` | RABBITMQ_PASSWORD, DB_PASSWORD, TAILSCALE_AUTH_KEY, CLOUDSQL_IP, GHCR_TOKEN | ✓ |
| `terraform/terraform.tfvars` | cloud credentials, db_password, ssh_public_key_path | ✓ |
| `terraform/terraform.tfstate` | live infrastructure state | ✓ |
| `bootstrap/gcp/key.json` | GCP service account key | ✓ |
| `/d/.ssh/k3s-config.yaml` | k3s cluster admin credentials | local only |
