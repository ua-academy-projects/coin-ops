# CoinOps k3s Deployment Guide

This document describes how the CoinOps application was deployed to a k3s Kubernetes cluster on GCP. It covers every step in order, the technologies used, and decisions made along the way.

---

## Technology Glossary

Before reading the deployment steps, here are the key technologies you need to understand.

**Kubernetes (k8s)** — a system for running and managing containerized applications across multiple machines. Instead of manually starting Docker containers on each VM, Kubernetes decides where to run them, restarts them if they crash, and distributes traffic between them.

**k3s** — a lightweight version of Kubernetes designed for edge and resource-constrained environments. Uses less RAM than full Kubernetes, ships as a single binary. Built into the install script — one command bootstraps a full cluster.

**Pod** — the smallest unit in Kubernetes. One or more containers that run together on the same machine. Each pod gets its own IP inside the cluster.

**Deployment** — a Kubernetes resource that says "run N copies of this pod and keep them running." If a pod crashes, Deployment restarts it automatically.

**Service** — gives a stable internal DNS name and IP to a group of pods. Without a Service, pods have random IPs that change on restart. With a Service, other pods always find them at `service-name.namespace.svc.cluster.local`.

**Namespace** — a logical grouping inside a Kubernetes cluster. Like folders on a filesystem. We use separate namespaces per concern: `coinops-queue`, `coinops-app`, `coinops-frontend`. This isolates services and makes it easier to manage permissions and resources.

**Ingress** — a Kubernetes resource that defines HTTP/HTTPS routing rules. "Requests for domain X go to Service Y." Ingress requires an Ingress controller to actually process the rules.

**Traefik** — the Ingress controller built into k3s. It watches Ingress resources and automatically configures itself to route traffic. Also handles TLS termination — it decrypts HTTPS traffic using certificates.

**Helm** — a package manager for Kubernetes. Like `apt` for Ubuntu but for Kubernetes apps. A Helm chart is a package containing all the YAML files needed to install an application. We use Helm to install cert-manager, Homepage, and Headlamp.

**HelmChartConfig** — a k3s-specific resource that lets you override values in a Helm chart that k3s manages internally (like Traefik). You describe what you want changed, k3s applies it via a Helm upgrade job.

**cert-manager** — a Kubernetes controller that automatically manages TLS certificates. It watches `Certificate` resources and requests certificates from Let's Encrypt. When a certificate is about to expire, it renews it automatically.

**Let's Encrypt** — a free Certificate Authority that issues TLS certificates. Uses ACME protocol to verify you own the domain before issuing a certificate.

**ACME HTTP-01 Challenge** — the verification method Let's Encrypt uses. It creates a temporary file at `http://your-domain/.well-known/acme-challenge/token`. Let's Encrypt fetches this file from the internet. If it gets the right response, you proved domain ownership and get a certificate.

**ClusterIssuer** — a cert-manager resource that defines how to get certificates (which CA, which challenge type, which email). Cluster-scoped — works across all namespaces.

**Secret** — a Kubernetes resource for storing sensitive data (passwords, tokens, TLS certificates). Base64-encoded but not encrypted by default. We use Secrets for database passwords, RabbitMQ passwords, and GHCR pull credentials.

**ConfigMap** — like a Secret but for non-sensitive configuration data. We use a ConfigMap to store the nginx configuration for the UI and the database schema SQL file.

**Job** — a Kubernetes resource that runs a pod once to completion. We use a Job for schema initialization — it runs `psql` to create tables in CloudSQL, then exits.

**GCP Regional NLB (Network Load Balancer)** — a Google Cloud load balancer that operates at Layer 4 (TCP). Pass-through mode means it forwards TCP packets unchanged to backend VMs. The backend (Traefik) receives the original connection from the client including the original TLS ClientHello — so Traefik can terminate TLS and read the Server Name Indication (SNI) to know which domain was requested.

**SNI (Server Name Indication)** — an extension to the TLS protocol. When a browser starts a TLS connection, it sends the domain name it wants to reach inside the ClientHello packet. This allows one server with one IP to host multiple HTTPS domains. Traefik reads SNI to route `coinops-softserve-penina.pp.ua` to the UI and `k3s.coinops-softserve-penina.pp.ua` to Homepage.

**CloudSQL** — GCP managed PostgreSQL. GCP handles backups, updates, and high availability. We access it via private IP through VPC peering — never exposed to the internet.

**VPC Peering** — connects two VPC networks so VMs in one can reach resources in another using private IPs. We use it to connect k3s VMs to CloudSQL.

**Ansible** — an automation tool that connects to servers via SSH and runs tasks defined in YAML files. Idempotent — running the same playbook twice produces the same result without breaking anything.

**Ansible Role** — a reusable collection of tasks organized by function. We have separate roles for k3s cluster setup, cert-manager, Homepage, Headlamp, and CoinOps.

**Terraform** — infrastructure as code tool. You describe the desired infrastructure in `.tf` files, Terraform figures out what to create, update, or delete to reach that state.

**GHCR (GitHub Container Registry)** — stores Docker images for the CoinOps services. Since the repo is private, k3s needs credentials (`imagePullSecret`) to pull images.

---

## Infrastructure Overview

```
Internet
  │
  ▼
Cloudflare DNS (grey cloud — DNS only, no proxy)
  │
  ▼
GCP Regional NLB 34.116.135.79
  port 80  → k3s nodes
  port 443 → k3s nodes (pass-through, TLS handled by Traefik)
  │
  ▼
k3s cluster (3 VMs, europe-central2)
  k3s-server-1  34.116.142.103 / 10.0.1.2  zone-a  control-plane+worker
  k3s-server-2  10.0.1.4                   zone-a  control-plane+worker
  k3s-server-3  10.0.1.3                   zone-b  control-plane+worker
  │
  ▼
Traefik (Ingress controller, built into k3s)
  coinops-softserve-penina.pp.ua    → UI pod (coinops-frontend namespace)
  k3s.coinops-softserve-penina.pp.ua → Homepage pod (homepage namespace)
  │
  ▼
CoinOps application
  coinops-queue:     rabbitmq, redis
  coinops-app:       proxy, history-api, history-consumer
  coinops-frontend:  nginx + React UI

Database: CloudSQL PostgreSQL (private IP 10.113.0.3)
```

---

## Step-by-Step Deployment

### Step 1 — Provision GCP Infrastructure with Terraform

**What Terraform creates:**
- VPC network and subnet in europe-central2
- Cloud Router + Cloud NAT (gives private VMs internet access for apt install)
- 3 e2-medium VMs with k3s-server tag
- GCP firewall rules (SSH on 9922, k3s ports, HTTP/HTTPS)
- CloudSQL PostgreSQL instance with private IP via VPC peering
- GCP service account for Terraform operations
- Regional NLB (Network Load Balancer) with TCP health check

```bash
export GOOGLE_APPLICATION_CREDENTIALS=/path/to/bootstrap/gcp/key.json
source .env  # sets CLOUDSQL_IP and other variables

cd terraform
terraform init -reconfigure
terraform apply -auto-approve
```

After apply, note these outputs:
- `gcp_lb_ip` — the LB public IP to set in Cloudflare DNS
- `gcp_db_endpoint` — CloudSQL private IP (already in .env via dynamic command)

**Why Regional NLB and not Global LB:** Global LB uses HTTP/TCP proxies that modify the connection. For HTTPS, a TCP proxy strips the TLS connection information. Traefik uses SNI (the domain name inside the TLS handshake) to route requests — without it, Traefik cannot determine which domain was requested and returns 404. Regional NLB in pass-through mode forwards the original TCP packets unchanged, so Traefik receives the complete TLS handshake including SNI.

---

### Step 2 — Update Cloudflare DNS

Go to Cloudflare DNS and set these A records pointing to the LB IP:

```
coinops-softserve-penina.pp.ua       A  34.116.135.79  DNS only
k3s.coinops-softserve-penina.pp.ua   A  34.116.135.79  DNS only
headlamp.coinops-softserve-penina.pp.ua A  34.116.135.79  DNS only
```

**Important — DNS only (grey cloud):** Cloudflare proxy (orange cloud) terminates HTTPS itself and re-encrypts to the origin. This breaks cert-manager's ACME HTTP challenge because Cloudflare intercepts the challenge verification request. DNS only mode passes all traffic directly to the LB IP.

---

### Step 3 — SSH to k3s-server-1 and Prepare

k3s-server-1 is the jump host for the cluster. All Ansible playbooks run from here.

```bash
# Start SSH agent (required for ProxyJump to private nodes)
eval $(ssh-agent)
ssh-add /d/.ssh/id_ed25519_devops

# Connect
ssh -A -p 9922 marta_ops@34.116.142.103

# On k3s-server-1:
# Copy SSH key so Ansible can reach k3s-server-2 and k3s-server-3
# (from local machine in another terminal)
scp -P 9922 /d/.ssh/id_ed25519_devops marta_ops@34.116.142.103:~/.ssh/id_ed25519
chmod 600 ~/.ssh/id_ed25519

# Clone/pull latest code
cd coin-ops
git pull origin dev-penina-cloud

# Load environment variables
source .env

# Install Ansible and dependencies
sudo apt install -y ansible python3-pip
pip3 install kubernetes --break-system-packages
ansible-galaxy install -r ansible/requirements.yml
```

**Why copy the SSH key to k3s-server-1:** Ansible runs from k3s-server-1 and SSHes to k3s-server-2 and k3s-server-3 via ProxyJump. For this to work, the private key must be available on k3s-server-1. SSH agent forwarding works for interactive sessions but not for Ansible connections from within the VM.

**Why `ansible-galaxy install`:** Our playbooks use `kubernetes.core` Ansible collection which provides `kubernetes.core.k8s` and `kubernetes.core.helm` modules. These are not part of the base Ansible installation. `ansible-galaxy` downloads them from the Ansible Galaxy registry.

---

### Step 4 — Bootstrap k3s Cluster

```bash
ansible-playbook -i ansible/inventory ansible/k3s-cluster.yml
```

**What this playbook does (in order):**

1. **common role** — on all 3 nodes: updates apt, installs base packages, sets timezone, configures UFW firewall with k3s-specific ports
2. **k3s_prereqs role** — on all 3 nodes: installs curl, Helm, pip3, Python kubernetes library
3. **k3s_server_bootstrap role** — on k3s-server-1 only: downloads k3s install script, runs it with `--cluster-init` flag to initialize etcd, waits for API to be ready, reads node join token
4. **k3s_server_join role** — on k3s-server-2 and k3s-server-3: downloads k3s install script, joins cluster using token and private IP of k3s-server-1
5. **k3s_postcheck role** — on k3s-server-1: waits for all nodes to show Ready status, copies kubeconfig to `/tmp/k3s-config.yaml` with public IP replacing localhost

**Why 3 control plane nodes:** k3s uses embedded etcd for cluster state. etcd requires a quorum (majority) to function. With 3 nodes, the cluster tolerates 1 node failure. With 2 nodes, any failure breaks the cluster. This is called high availability (HA).

**Why `--tls-san {{ ansible_host }}`:** k3s generates a TLS certificate for its API server. By default it's only valid for localhost and private IPs. We add the public IP as a Subject Alternative Name (SAN) so kubectl can connect from your laptop using the public IP without a certificate error.

After the playbook, copy kubeconfig to your laptop:

```bash
scp -P 9922 marta_ops@34.116.142.103:/tmp/k3s-config.yaml /d/.ssh/k3s-config.yaml
export KUBECONFIG=/d/.ssh/k3s-config.yaml
kubectl get nodes  # should show 3 nodes Ready
```

---

### Step 5 — Deploy Applications

```bash
ansible-playbook -i ansible/inventory ansible/k3s-apps.yml
```

**What this playbook deploys (in order):**

#### cert-manager
Installs cert-manager via Helm into `cert-manager` namespace. Creates a `ClusterIssuer` resource pointing to Let's Encrypt production API. The ClusterIssuer uses HTTP-01 challenge with `ingressClassName: traefik` — this tells cert-manager to create solver Ingress resources with Traefik class so Traefik picks them up.

#### Headlamp
Installs Headlamp Kubernetes dashboard via Helm. No public Ingress — accessible only via port-forward. Admin tools should not be exposed to the internet.

#### Homepage
Installs Homepage dashboard via Helm. Creates Ingress with TLS annotation `cert-manager.io/cluster-issuer: letsencrypt-prod` — this triggers cert-manager to automatically request a certificate for `k3s.coinops-softserve-penina.pp.ua`.

#### CoinOps (k3s_coinops role)

The role deploys in this exact order:

**1. Namespaces** — creates `coinops-queue`, `coinops-app`, `coinops-frontend`

**2. Secrets** — creates in all namespaces:
- `ghcr-pull-secret` — Docker credentials for pulling images from GHCR
- `queue-secret` — RabbitMQ password
- `app-secret` — database URL, RabbitMQ URL, Redis URL

**Why secrets before deployments:** Kubernetes tries to mount secrets when creating pods. If a secret doesn't exist yet, the pod fails to start with `CreateContainerConfigError`. Creating secrets first prevents this race condition.

**3. Queue layer** — deploys RabbitMQ and Redis in `coinops-queue` namespace with ClusterIP Services. Other services reach them via DNS: `rabbitmq.coinops-queue.svc.cluster.local`.

**4. App layer:**
- Copies `schema.sql` to k3s-server-1
- Creates ConfigMap from the SQL file
- Runs schema-init Job — mounts the ConfigMap and runs `psql` against CloudSQL to create tables
- Waits for Job to complete (required — history-api fails if tables don't exist)
- Deploys history-api, history-consumer, proxy in `coinops-app` namespace

**5. Frontend layer** — deploys nginx UI in `coinops-frontend` namespace with Ingress and TLS. cert-manager detects the TLS annotation, creates a Certificate resource, runs ACME challenge, and stores the certificate as a Secret that Traefik uses.

---

### Step 6 — Verify Deployment

```bash
# All pods should be Running (schema-init shows Completed — that's correct)
kubectl get pods -A

# Certificates should show READY: True
kubectl get certificate -A

# No pending challenges
kubectl get challenges -A

# LB backends should be HEALTHY
gcloud compute backend-services get-health coinops-k3s-backend-http \
  --region=europe-central2 --project=devops-intern-penina
```

**Expected pod status:**
```
coinops-app        coinops-schema-init   Completed   ← ran once, created tables
coinops-app        history-api           Running     ← REST API for price history
coinops-app        history-consumer      Running     ← reads from RabbitMQ, writes to DB
coinops-app        proxy                 Running     ← Go API gateway
coinops-frontend   ui                    Running     ← nginx + React SPA
coinops-queue      rabbitmq              Running     ← message queue
coinops-queue      redis                 Running     ← cache
cert-manager       cert-manager          Running     ← certificate controller
homepage           homepage              Running     ← dashboard
headlamp           headlamp              Running     ← k8s UI (port-forward only)
```

---

### Step 7 — Access Services

**CoinOps application:**
```
https://coinops-softserve-penina.pp.ua
```

**Homepage dashboard:**
```
https://k3s.coinops-softserve-penina.pp.ua
```

**Headlamp (Kubernetes dashboard — local access only):**
```bash
export KUBECONFIG=/d/.ssh/k3s-config.yaml
kubectl port-forward -n headlamp svc/headlamp 8080:80
# Open: http://localhost:8080
# Generate token:
kubectl create token headlamp-admin -n headlamp
```

---

## Key Decisions

### Why CloudSQL instead of PostgreSQL StatefulSet

A StatefulSet would run PostgreSQL inside the cluster. If the pod restarts or the node fails, there is a risk of data loss or corruption. CloudSQL is a managed service — GCP handles backups, replication, updates, and failover. For production workloads, managed databases are the correct choice.

### Why Headlamp has no public Ingress

Headlamp has full admin access to the Kubernetes cluster. Exposing it publicly means anyone who finds the URL can attempt to log in. The correct approach is to require VPN or SSH tunnel access to admin tools. Port-forward creates a tunnel from your laptop — no public exposure.

### Why separate namespaces

Separating services into namespaces (`coinops-queue`, `coinops-app`, `coinops-frontend`) provides:
- Clear ownership and purpose boundaries
- Independent secret management per namespace
- Ability to apply different resource limits or network policies per namespace
- Easier cleanup — `kubectl delete namespace coinops-app` removes everything in that layer

### Why env variable for CloudSQL IP

Infrastructure values (like database IPs) should not be hardcoded in Ansible files. They should flow from the source of truth (Terraform) to the consumer (Ansible) via environment variables. The `.env` file reads the value dynamically:
```bash
export CLOUDSQL_IP=$(cd /path/to/terraform && terraform output -raw gcp_db_endpoint)
```
This way if CloudSQL is recreated and gets a new IP, running `source .env` picks it up automatically without editing any files.

---

## Troubleshooting

**Certificates stuck in False / challenges pending:**
```bash
kubectl describe challenge <name> -n <namespace>
# Look at "Reason" field — usually shows HTTP status code
# 502 = LB health check failing, backends UNHEALTHY
# 404 = Traefik not routing to solver pod (check ingressClassName)
```

**Pods not starting:**
```bash
kubectl describe pod <name> -n <namespace>
# Check Events section at the bottom
# Common causes: missing secret, image pull error, resource limits
```

**LB backends UNHEALTHY:**
```bash
gcloud compute backend-services get-health coinops-k3s-backend-http \
  --region=europe-central2 --project=devops-intern-penina
# If UNHEALTHY: TCP health check on port 80 is failing
# Verify Traefik is running: kubectl get pods -n kube-system | grep traefik
```

**Cannot connect to k3s-server-1:**
```bash
# SSH agent not running
eval $(ssh-agent)
ssh-add /d/.ssh/id_ed25519_devops
ssh -A -p 9922 marta_ops@34.116.142.103
# Note: 34.116.135.79 is the LB IP — use 34.116.142.103 for SSH
```
