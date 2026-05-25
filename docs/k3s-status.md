# Task 2 + Task 3 — k3s Cluster + Ingress + Apps

Branch: `dev-penina-cloud` | Owner: Marta Penina

---

## Task 2 — k3s Kubernetes Cluster on GCP

### Status: 🔄 In Progress (cluster bootstrapping)

### What was done

**Terraform — GCP Infrastructure:**
- 3 GCP VMs: `k3s-server-1` (public), `k3s-server-2`, `k3s-server-3` (private)
- Machine type: `e2-medium` (2 vCPU, 4GB RAM) — minimum required for k3s
- GCP VPC + subnet `10.0.1.0/24`
- Cloud NAT — gives private nodes outbound internet access (for apt, docker pull)
- Firewall rules: SSH (9922), k3s API (6443), etcd (2379-2380), Flannel (8472 UDP), kubelet (10250)
- Startup script via `templatefile()` — fixes Windows CRLF line ending issue

**Ansible — k3s Roles:**

| Role | Runs on | What it does |
|------|---------|--------------|
| `k3s_prereqs` | all 3 nodes | installs curl, open-iscsi, nfs-common |
| `k3s_server_bootstrap` | k3s-server-1 only | initializes cluster with `--cluster-init`, saves join token |
| `k3s_server_join` | k3s-server-2, k3s-server-3 | joins existing cluster using token from bootstrap |
| `k3s_postcheck` | k3s-server-1 | verifies all nodes Ready, fetches kubeconfig locally |

**Playbook:** `ansible/k3s-cluster.yml`

### Expected Result

```bash
kubectl get nodes
NAME           STATUS   ROLES                       AGE
k3s-server-1   Ready    control-plane,etcd,master   5m
k3s-server-2   Ready    control-plane,etcd,master   3m
k3s-server-3   Ready    control-plane,etcd,master   2m
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

---

## Task 2 Bonus — Headlamp

### Status: ⏳ Pending (after cluster is up)

**What is Headlamp:**
Headlamp is a Kubernetes UI dashboard. It runs inside the cluster as a pod and gives you a visual interface to see all workloads, pods, deployments, logs — everything you can do with `kubectl` but in a browser.

Think of it as: `kubectl` = terminal access, Headlamp = visual interface for the same cluster.

**Installation:** via Helm through Ansible role `k3s_headlamp`

```
ansible/roles/k3s_headlamp/
  tasks/main.yml    ← installs Headlamp via kubernetes.core.helm
```

**Access:** `https://headlamp.coinops-softserve-penina.pp.ua`

---

## Task 3 — Ingress + TLS + Homepage + Headlamp

### Status: ⏳ Pending

### What needs to be done

**cert-manager** — automates TLS certificates from Let's Encrypt
- Watches for `Certificate` resources
- Automatically requests and renews certificates
- No manual certificate management needed
- Ansible role: `cert_manager`

**Ingress (Traefik)** — k3s ships Traefik by default
- Routes external HTTP/HTTPS traffic to the right service
- `coinops-softserve-penina.pp.ua` → Homepage service
- `headlamp.coinops-softserve-penina.pp.ua` → Headlamp service

**Homepage** — lightweight dashboard (gethomepage.dev)
- Shows links to all your services
- Status indicators
- Customizable bookmarks
- Ansible role: `k3s_homepage`

**Headlamp** — Kubernetes UI (already described above)
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

### Expected Result

```
https://coinops-softserve-penina.pp.ua          → Homepage dashboard
https://headlamp.coinops-softserve-penina.pp.ua → Headlamp Kubernetes UI
```

Both with valid TLS certificates (green padlock in browser).

---

## Architecture Overview

```
Internet
  │
  ▼
Cloudflare (DNS + HTTPS proxy)
  │
  ▼
GCP Load Balancer / Traefik Ingress (k3s-server-1)
  │
  ├── coinops-softserve-penina.pp.ua  → Homepage pod
  └── headlamp.coinops-softserve-penina.pp.ua → Headlamp pod

GCP k3s Cluster:
  k3s-server-1 (control plane + worker, public IP)
  k3s-server-2 (control plane + worker, private)
  k3s-server-3 (control plane + worker, private)
```
