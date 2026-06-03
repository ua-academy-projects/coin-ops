# CoinOps — Cloud Deployment

Personal cloud deployment branch: `dev-penina-cloud`
Owner: Marta Penina (@MartaPenina)
Based on: `dev` branch of [ua-academy-projects/coin-ops](https://github.com/ua-academy-projects/coin-ops)

---

## What This Branch Does

Deploys the CoinOps application to a k3s Kubernetes cluster on GCP using:
- **Terraform** — provisions GCP infrastructure (VMs, VPC, Regional NLB, firewall rules)
- **Ansible** — configures VMs, installs k3s cluster, deploys infrastructure apps
- **Helm** — deploys CoinOps application stack with per-service namespace isolation
- **k3s** — lightweight Kubernetes cluster on GCP (3 nodes, all control plane + worker)
- **CNPG (CloudNativePG)** — PostgreSQL running inside k3s cluster (replaces external Cloud SQL)
- **cert-manager** — automatic TLS certificates via Let's Encrypt
- **Traefik** — Ingress controller (built into k3s)
- **Cloudflare** — DNS management
- **GCP Regional NLB** — pass-through Network Load Balancer for k3s cluster

---

## Application URLs

| Service | URL | Access |
|---------|-----|--------|
| CoinOps | https://coinops-softserve-penina.pp.ua | Public ✅ |
| Homepage | https://k3s.coinops-softserve-penina.pp.ua | Public ✅ |
| Headlamp | http://localhost:8080 | Port-forward only (admin tool — not public by design) |

---

## Architecture

```
Internet
  │
  ▼
Cloudflare DNS (DNS only — no proxy)
  │
  ▼
GCP Regional NLB 34.116.208.65 (pass-through — forwards TCP packets unchanged)
  │
  ├── port 80  → k3s nodes → Traefik → HTTP routes
  └── port 443 → k3s nodes → Traefik → HTTPS routes (TLS terminated by Traefik)
                                  │
                        ┌─────────┴──────────┐
                        ▼                    ▼
              coinops-softserve-        k3s.coinops-
               penina.pp.ua             softserve-penina.pp.ua
               (coinops-ui ns)          (homepage ns)

GCP k3s Cluster (europe-central2):
  k3s-server-1  control plane + worker  34.116.219.249 (public) / 10.0.1.4 (private)
  k3s-server-2  control plane + worker  10.0.1.2 (private)
  k3s-server-3  control plane + worker  10.0.1.3 (private, zone-b)
```

---

## Kubernetes Namespaces

Each service runs in its own isolated namespace:

| Namespace | Service | Purpose |
|-----------|---------|---------|
| `coinops-rabbitmq` | RabbitMQ | Message queue for async communication |
| `coinops-redis` | Redis | Cache layer for proxy |
| `coinops-proxy` | Go proxy | Central API hub, fetches market data |
| `coinops-history-api` | Python history API | Serves historical data to UI |
| `coinops-history-consumer` | Python worker | Consumes RabbitMQ, writes to DB |
| `coinops-ui` | React + nginx | Frontend, public via Ingress |
| `coinops-db` | CNPG PostgreSQL | In-cluster database |
| `cert-manager` | cert-manager | TLS certificate automation |
| `homepage` | Homepage | Cluster dashboard |
| `headlamp` | Headlamp | Kubernetes UI (port-forward only) |
| `cnpg-system` | CNPG operator | CloudNativePG operator |

---

## GCP Infrastructure

| Resource | Zone | Role | Public IP | Private IP |
|----------|------|------|-----------|------------|
| k3s-server-1 | europe-central2-a | control plane + worker | 34.116.219.249 | 10.0.1.4 |
| k3s-server-2 | europe-central2-a | control plane + worker | — | 10.0.1.2 |
| k3s-server-3 | europe-central2-b | control plane + worker | — | 10.0.1.3 |
| Regional NLB | europe-central2 | Pass-through LB | 34.116.208.65 | — |

---

## Deployment — How It Works

### 1. Infrastructure (Terraform)
```bash
cd terraform
terraform init -reconfigure
terraform apply -auto-approve
```

### 2. k3s Cluster (Ansible)
```bash
# On k3s-server-1
ansible-playbook -i ansible/inventory ansible/k3s-cluster.yml
```

### 3. Infrastructure Apps (Ansible)
Deploys: cert-manager, Headlamp, Homepage, CNPG operator
```bash
ansible-playbook -i ansible/inventory ansible/k3s-apps.yml
```

### 4. CoinOps Application (Helm)
```bash
helm upgrade --install coinops helm/coinops \
  --set secrets.dbPassword="$DB_PASSWORD" \
  --set secrets.rabbitmqPassword="$RABBITMQ_PASSWORD" \
  --set secrets.ghcrToken="$GHCR_TOKEN" \
  --set secrets.ghcrUsername="$GHCR_USERNAME"
```

---

## Ansible Roles

| Role | Purpose |
|------|---------|
| `common` | UFW firewall, apt packages, timezone |
| `k3s_prereqs` | curl, Helm, pip3, python kubernetes library |
| `k3s_server` | initializes cluster on node-1, joins node-2 and node-3 (single role with `when` conditions) |
| `k3s_postcheck` | verifies all nodes Ready, downloads kubeconfig |
| `cert_manager` | installs cert-manager + Let's Encrypt ClusterIssuer |
| `k3s_headlamp` | installs Headlamp UI + ServiceAccount (port-forward only) |
| `k3s_homepage` | installs Homepage dashboard + Ingress + TLS |
| `k3s_cnpg` | installs CNPG operator + creates PostgreSQL cluster |

---

## Helm Chart Structure

```
helm/coinops/
  Chart.yaml              — chart metadata
  values.yaml             — all configurable values (namespaces, images, ports)
  templates/
    _helpers.tpl          — common labels used by all resources
    namespaces.yaml       — creates all per-service namespaces
    secrets.yaml          — GHCR pull secrets + app credentials per namespace
    rabbitmq.yaml         — RabbitMQ Deployment + Service
    redis.yaml            — Redis Deployment + Service
    proxy.yaml            — Go proxy Deployment + Service (with initContainers)
    history.yaml          — history-api Deployment + Service
    history-consumer.yaml — history-consumer Deployment
    ui.yaml               — UI Deployment + Service + Ingress
    cnpg-cluster.yaml     — CloudNativePG Cluster resource (PostgreSQL)
    networkpolicies.yaml  — per-namespace NetworkPolicies (default-deny + allow rules)
```

---

## Headlamp Access (port-forward only)

```bash
# On k3s-server-1 — open SSH tunnel first
ssh -p 9922 -L 8080:localhost:8080 marta_ops@34.116.219.249

# Then on k3s-server-1
export KUBECONFIG=~/.kube/config
kubectl port-forward -n headlamp svc/headlamp 8080:80

# Get token
kubectl create token headlamp-admin -n headlamp

# Open in browser
# http://localhost:8080
```

---

## kubectl Access

```bash
# Copy kubeconfig from k3s-server-1
scp -P 9922 marta_ops@34.116.219.249:~/.kube/config /d/.ssh/k3s-config.yaml

export KUBECONFIG=/d/.ssh/k3s-config.yaml
kubectl get nodes
kubectl get pods -A
```

---

## Problems & Solutions

**Problem 1 — GCP Global LB did not pass Host header**
Global TCP proxy forwarded raw TCP bytes. Traefik uses host-based routing → returned 404.
Fix: replaced with Regional NLB (pass-through mode). Regional NLB forwards TCP packets unchanged.

**Problem 2 — Health check returned 404, backends UNHEALTHY**
HTTP health check sent GET /health without Host header → Traefik returned 404 → GCP marked backends UNHEALTHY.
Fix: TCP health check on port 80. Verifies port is open without requiring HTTP response.

**Problem 3 — cert-manager ACME solver Ingress had no IngressClass**
cert-manager created solver Ingress with class: none → Traefik ignored it → ACME challenge returned 502.
Fix: ingressClassName: traefik in ClusterIssuer solver config.

**Problem 4 — NetworkPolicy blocked Traefik from reaching UI**
Default-deny NetworkPolicy blocked all ingress including from Traefik.
Fix: added allow-traefik NetworkPolicy in coinops-ui namespace allowing ingress from kube-system/traefik pod.

**Problem 5 — VPC peering could not be deleted via Terraform**
Cloud SQL was deleted but service networking connection remained due to GCP cache.
Fix: manually deleted VPC peering in GCP Console → then terraform apply succeeded.

---

## Next Steps

- [ ] **Cloudflare Tunnel (cloudflared)** — replace public NLB with Cloudflare Tunnel for zero-trust access. No public IP needed. Headlamp accessible via private tunnel without port-forward.
- [ ] **ArgoCD / GitOps** — replace manual helm upgrade with GitOps-based continuous deployment
- [ ] **Monitoring** — Prometheus + Grafana in separate namespace
- [ ] **Logging** — Loki + Promtail

---

## Secrets — Never Commit

| File | Contains | Gitignored |
|------|---------|-----------|
| `.env` | DB_PASSWORD, RABBITMQ_PASSWORD, GHCR_TOKEN, GHCR_USERNAME | ✓ |
| `terraform/terraform.tfvars` | GCP credentials, db_password, ssh_public_key_path | ✓ |
| `terraform/terraform.tfstate` | live infrastructure state | ✓ |
| `bootstrap/gcp/key.json` | GCP service account key | ✓ |
| `~/.kube/config` | k3s cluster admin credentials | local only |
