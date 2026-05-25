# Task 2 + Task 3 — k3s Cluster + Ingress + Apps

Branch: `dev-penina-cloud` | Owner: Marta Penina

---

## Task 2 — k3s Kubernetes Cluster on GCP

### Status: ✅ Complete

### What was done

**Terraform — GCP Infrastructure:**
- 3 GCP VMs: `k3s-server-1` (public), `k3s-server-2`, `k3s-server-3` (private)
- Machine type: `e2-medium` (2 vCPU, 4GB RAM) — minimum required for k3s
- GCP VPC + subnet `10.0.1.0/24`
- Cloud NAT + Cloud Router — gives private nodes outbound internet access (for apt, docker pull)
- Firewall rules: SSH (9922), k3s API (6443), etcd (2379-2380), Flannel (8472 UDP), kubelet (10250), HTTP/HTTPS (80/443)
- Startup script via `templatefile()` — fixes Windows CRLF line ending issue
- `--tls-san` flag — adds public IP to k3s TLS certificate so kubectl works from outside

**Ansible — k3s Roles:**

| Role | Runs on | What it does |
|------|---------|--------------|
| `k3s_prereqs` | all 3 nodes | installs curl, open-iscsi, nfs-common, Helm, pip3, python kubernetes library |
| `k3s_server_bootstrap` | k3s-server-1 only | initializes cluster with `--cluster-init --tls-san`, saves join token |
| `k3s_server_join` | k3s-server-2, k3s-server-3 | joins existing cluster using token from bootstrap |
| `k3s_postcheck` | k3s-server-1 | verifies all nodes Ready, fetches kubeconfig locally |

**Playbook:** `ansible/k3s-cluster.yml`

### Result

```bash
kubectl get nodes
NAME                                                             STATUS   ROLES                       AGE   VERSION
k3s-server-1.europe-central2-a.c.devops-intern-penina.internal  Ready    control-plane,etcd,master   1h    v1.31.0+k3s1
k3s-server-2.europe-central2-a.c.devops-intern-penina.internal  Ready    control-plane,etcd,master   1h    v1.31.0+k3s1
k3s-server-3.europe-central2-b.c.devops-intern-penina.internal  Ready    control-plane,etcd,master   1h    v1.31.0+k3s1
```

### GCP Resources

| Resource | Value |
|----------|-------|
| k3s-server-1 | 34.158.238.181 (public) / 10.0.1.11 |
| k3s-server-2 | 10.0.1.12 (private) |
| k3s-server-3 | 10.0.1.13 (private) |
| GCP Project | devops-intern-penina |
| Region | europe-central2 |

### Problems & Solutions

**Problem: startup script had Windows CRLF line endings**
GCP could not execute the script: `cannot execute: required file not found`
Fix: moved script to separate `startup.sh` file + `.gitattributes` with `*.sh eol=lf`

**Problem: private nodes had no internet access**
k3s-server-2/3 could not run `apt install` — no outbound internet
Fix: added Cloud NAT + Cloud Router in `gcp_network/main.tf`

**Problem: all firewall rules had `count = cloud == "gcp"` — skipped in hybrid mode**
Fix: changed to `contains(["gcp", "hybrid"], var.config.general.cloud)`

**Problem: k3s-server-2/3 joining via public IP — connection refused**
k3s join used `ansible_host` (public IP 34.158.238.181) instead of private IP. GCP firewall allow-k3s only allows traffic between k3s-server tags via internal IP.
Fix: changed `k3s_server_ip` fact to use `ansible_default_ipv4.address` (private IP 10.0.1.11)

**Problem: kubectl TLS error — certificate valid for private IPs only**
k3s generates TLS cert only for private IPs by default. kubectl from laptop connects via public IP → certificate mismatch.
Fix: added `--tls-san {{ ansible_host }}` to bootstrap install command

**Problem: UFW blocked k3s ports between nodes**
common role only opened port 9922. k3s needs 6443, 9345, 2379-2380, 8472 UDP, 10250.
Fix: added `common_allowed_ports` and `common_allowed_udp_ports` override in `[k3s_server:vars]` in inventory

---

## Task 2 Bonus — Headlamp

### Status: ✅ Complete

**What is Headlamp:**
Headlamp is a Kubernetes UI dashboard. It runs inside the cluster as a pod and gives you a visual interface to see all workloads, pods, deployments, logs — everything you can do with `kubectl` but in a browser.

Think of it as: `kubectl` = terminal access, Headlamp = visual interface for the same cluster.

**Installation:** via Helm through Ansible role `k3s_headlamp`

```
ansible/roles/k3s_headlamp/
  tasks/main.yml      ← installs Headlamp via kubernetes.core.helm, creates Ingress
  defaults/main.yml   ← namespace, domain variables
```

**Access:** `https://headlamp.coinops-softserve-penina.pp.ua`

**Authentication:** requires Service Account token generated via:
```bash
kubectl create serviceaccount headlamp-admin -n headlamp
kubectl create clusterrolebinding headlamp-admin --clusterrole=cluster-admin --serviceaccount=headlamp:headlamp-admin
kubectl create token headlamp-admin -n headlamp
```

---

## Task 3 — Ingress + TLS + Homepage + Headlamp

### Status: ✅ Complete

### What was done

**cert-manager** — automates TLS certificates from Let's Encrypt
- Watches for `Certificate` resources in Ingress annotations
- Automatically requests and renews certificates via HTTP-01 challenge
- No manual certificate management needed
- Ansible role: `cert_manager`
- ClusterIssuer: `letsencrypt-prod`

**Ingress (Traefik)** — k3s ships Traefik by default, no installation needed
- Routes external HTTP/HTTPS traffic to the right service based on hostname
- `k3s.coinops-softserve-penina.pp.ua` → Homepage service
- `headlamp.coinops-softserve-penina.pp.ua` → Headlamp service

**Homepage** — lightweight dashboard (gethomepage.dev)
- Shows system stats (CPU, RAM)
- Bookmarks: Headlamp, GitHub repo
- Ansible role: `k3s_homepage`

**Headlamp** — Kubernetes UI (see Task 2 Bonus above)
- Ansible role: `k3s_headlamp`

### Key principle from mentor

Use Kubernetes-native Ansible modules — not shell commands:
```yaml
# CORRECT
- kubernetes.core.helm      ← install Helm charts
- kubernetes.core.k8s       ← apply manifests

# AVOID
- shell: helm install ...
- shell: kubectl apply -f ...
```

### Playbook

`ansible/k3s-apps.yml` — installs all apps in order:
1. cert_manager
2. k3s_headlamp
3. k3s_homepage

### Result

```
https://k3s.coinops-softserve-penina.pp.ua          → Homepage dashboard ✅
https://headlamp.coinops-softserve-penina.pp.ua     → Headlamp Kubernetes UI ✅
```

Both with valid TLS certificates from Let's Encrypt (green padlock).

### Problems & Solutions

**Problem: Helm not found on k3s-server-1**
`kubernetes.core.helm` requires Helm binary on the target node.
Fix: added Helm installation to `k3s_prereqs` role

**Problem: `kubernetes` Python library missing**
`kubernetes.core.k8s` requires Python kubernetes library.
Fix: added `python3-pip` + `pip install kubernetes` to `k3s_prereqs` role

**Problem: KUBECONFIG not set for Helm**
Helm defaulted to `localhost:8080` instead of k3s config.
Fix: added `environment: KUBECONFIG: /etc/rancher/k3s/k3s.yaml` to all plays in `k3s-apps.yml`

**Problem: Let's Encrypt rejected email `marta.penina@devops`**
Domain `.devops` does not exist — invalid contact email.
Fix: changed to `marta.penina.academic@gmail.com`

**Problem: Homepage showing "Host validation failed"**
Homepage (Next.js) validates Host header — rejects unknown domains by default.
Fix: added `HOMEPAGE_ALLOWED_HOSTS` env variable in Helm values

---

## Architecture Overview

```
Internet
  │
  ▼
Cloudflare (DNS only — k3s.* and headlamp.*)
  │
  ▼
34.158.238.181 (k3s-server-1 public IP)
  │
  ▼
Traefik Ingress (built into k3s)
  │
  ├── k3s.coinops-softserve-penina.pp.ua      → Homepage pod (namespace: homepage)
  └── headlamp.coinops-softserve-penina.pp.ua → Headlamp pod (namespace: headlamp)

GCP k3s Cluster:
  k3s-server-1 (control plane + worker, public IP 34.158.238.181)
  k3s-server-2 (control plane + worker, private 10.0.1.12)
  k3s-server-3 (control plane + worker, private 10.0.1.13)

cert-manager (namespace: cert-manager)
  └── ClusterIssuer: letsencrypt-prod
        └── HTTP-01 challenge via Traefik
```
