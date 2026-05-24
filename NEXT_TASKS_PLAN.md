# CoinOps — Next Tasks Plan

Branch: `dev-penina-cloud`

---

## Overview & Time Estimate

| Task | Description | Estimated Time |
|------|-------------|----------------|
| Task 1 | Tailscale subnet router fix | 1–1.5 hours |
| Task 2 | k3s cluster on GCP (3 nodes via Terraform + Ansible) | 3–4 hours |
| Task 3 | Ingress + TLS certs + Homepage + Headlamp | 2–3 hours |
| **Total** | | **6–8.5 hours** |

---

## Task 1 — Fix Tailscale: Subnet Router on Jump-Host

**Problem with the current approach:**
Tailscale was installed on every VM individually. The mentor's feedback: this is not the right pattern. In each isolated network (AWS VPC, Azure VNet, GCP VPC) there should be **one** Tailscale node that acts as a **subnet router** — it advertises its entire subnet to the tailnet, so all other VMs in that subnet become reachable without running Tailscale themselves.

**Why this is better:**
- Fewer attack surface points (only one node per network has Tailscale)
- Other VMs stay fully private
- Matches production practice
- Scales cleanly: add a new VM → it's automatically reachable via the router

**Architecture after fix:**

```
AWS VPC (10.0.0.0/16)
  └── jump-host (Tailscale ON, advertises 10.0.0.0/16)
        ├── node-01 (Tailscale OFF — reachable via jump-host subnet route)
        └── node-02 (Tailscale OFF — reachable via jump-host subnet route)

Azure VNet (10.0.0.0/16)
  └── jump-host-azure (Tailscale ON, advertises Azure subnet)

GCP VPC (10.20.0.0/16)
  └── jump-host-gcp (Tailscale ON, advertises GCP subnet)

All three subnets talk to each other through Tailscale advertised routes.
```

### Step-by-Step

**Step 1 — Understand the Tailscale subnet router setting**

Read: https://tailscale.com/kb/1019/subnets

The key flag is `--advertise-routes=10.0.0.0/16` when running `tailscale up`. This tells Tailscale: "route all traffic for this CIDR through me."

On the Tailscale admin panel you also need to **approve** the advertised routes for the machine.

**Step 2 — Create/update Ansible role `tailscale_gateway`**

The role should live at `ansible/roles/tailscale_gateway/`. It runs only on jump-host nodes (not on all nodes).

The role does:
1. Install Tailscale (add apt repo + install package)
2. Start `tailscaled` daemon
3. Run `tailscale up --authkey=... --advertise-routes=<subnet_cidr> --accept-routes`

Variables the role needs (in `defaults/main.yml`):
```yaml
tailscale_auth_key: ""          # from .env / ansible extra-vars
tailscale_advertise_routes: ""  # e.g. "10.0.0.0/16"
tailscale_hostname: ""          # e.g. "jump-host-aws"
```

**Step 3 — Update `ansible/provision.yml`**

The tailscale_gateway role should only run on the `jump_host` group, not `all`:

```yaml
- name: Install Tailscale subnet router on jump-host
  hosts: jump_host
  become: yes
  roles:
    - tailscale_gateway
```

**Step 4 — Approve routes in Tailscale admin**

After provision runs: go to https://login.tailscale.com/admin/machines, find jump-host, click the three dots → Edit route settings → enable the advertised subnet.

**Step 5 — Update `ansible/inventory`**

After Tailscale is up on jump-host: other nodes (node-01, node-02) become reachable through the subnet route. The `ansible_ssh_common_args` for internal nodes should use jump-host as a ProxyJump:

```ini
[history]
node-01 ansible_host=10.0.x.x   # private IP, reachable via subnet route

[proxy]
node-02 ansible_host=10.0.x.x

[all:vars]
ansible_ssh_common_args=-o ProxyJump=marta_ops@<jump-host-ip>:9922 -o StrictHostKeyChecking=no
```

**Step 6 — Remove public IPs from node-01 and node-02**

In `config.yaml` set back:
```yaml
node-01:
  public_ip: false
node-02:
  public_ip: false
```

Run `terraform apply` — nodes move back to private subnet.

---

## Task 2 — k3s Kubernetes Cluster on GCP

### Background — Read Before Starting

**What is k3s?**
k3s is a lightweight Kubernetes distribution by Rancher. It packages everything needed (API server, scheduler, controller, etcd-replacement) into a single binary under 100MB. Designed for resource-constrained environments. Runs on 2GB RAM minimum but 4GB recommended.

**Control plane vs worker nodes:**

| Type | Also called | Responsibilities |
|------|-------------|-----------------|
| Server node | Control plane | Runs API server, scheduler, etcd, controller manager. Accepts `kubectl` commands. Decides where to place pods. |
| Agent node | Worker node | Runs actual workloads (pods/containers). Reports to server. |
| Server+Worker | Combined (our case) | Runs everything — control plane AND workloads. Used for small clusters. |

In our 3-node cluster: **all 3 nodes are server nodes** (they run control plane AND accept workloads). No separation of concerns — this is fine for learning and small deployments.

**k3s bootstrap sequence:**
1. First server node initializes the cluster (`k3s server --cluster-init`)
2. Remaining nodes join via the first node's IP and a join token
3. After all nodes are joined, any node can be used to run `kubectl`

### Step-by-Step

**Step 1 — Terraform: add 3 GCP VMs**

In `terraform/config.yaml`, add 3 GCP k3s nodes:

```yaml
vms:
  k3s-server-1:
    cloud: "gcp"
    size: medium      # e2-small minimum, e2-medium for comfort
    zone: primary
    tags: ["k3s-server"]
    public_ip: true

  k3s-server-2:
    cloud: "gcp"
    size: medium
    zone: primary
    tags: ["k3s-server"]
    public_ip: false

  k3s-server-3:
    cloud: "gcp"
    size: medium
    zone: secondary
    tags: ["k3s-server"]
    public_ip: false
```

VM size note: GCP `e2-small` = 2 vCPU, 2GB RAM — bare minimum for k3s. `e2-medium` = 2 vCPU, 4GB RAM — recommended.

**Step 2 — GCP firewall rules**

Add to `modules/gcp_security/main.tf` — k3s needs these ports open between nodes:
- TCP 6443 — Kubernetes API server
- TCP 9345 — k3s supervisor API (for node join)
- TCP 2379-2380 — etcd peer communication
- UDP 8472 — Flannel VXLAN overlay network
- TCP 10250 — kubelet metrics

**Step 3 — Ansible inventory**

Add a new group in `ansible/inventory`:

```ini
[role_k3s_server]
k3s-server-1 ansible_host=<public-ip>
k3s-server-2 ansible_host=<private-ip>
k3s-server-3 ansible_host=<private-ip>
```

(Servers 2 and 3 connect via jump on server-1 or directly if in same VPC.)

**Step 4 — Ansible roles structure**

Extend the existing Ansible config. Create these roles:

```
ansible/roles/
  k3s_prereqs/        ← installs dependencies (curl, apt packages)
    tasks/main.yml
  k3s_server_bootstrap/ ← initializes the FIRST server node
    tasks/main.yml
  k3s_server_join/    ← joins remaining nodes to cluster
    tasks/main.yml
  k3s_postcheck/      ← validates cluster, fetches kubeconfig
    tasks/main.yml
```

Why separate roles:
- `k3s_server_bootstrap` runs only on node 1 (the initializer)
- `k3s_server_join` runs on nodes 2 and 3
- Roles can call other roles via `include_role` — this is what the mentor showed in the screenshot
- Avoids code duplication

**Step 5 — `ansible/k3s-cluster.yml` playbook**

```yaml
# Play 1: prepare all k3s nodes
- name: Prepare k3s server nodes
  hosts: role_k3s_server
  pre_tasks:
    - name: Wait for SSH to be stable
      wait_for_connection:
        sleep: 5
        delay: 5
    - name: Gather facts
      setup:
  roles:
    - common
    - k3s_prereqs

# Play 2: bootstrap first server
- name: Bootstrap the first k3s server
  hosts: "{{ groups.get('role_k3s_server', ['localhost']) | sort | first }}"
  become: yes
  gather_facts: no
  roles:
    - k3s_server_bootstrap

# Play 3: join remaining servers
- name: Join the remaining k3s servers
  hosts: role_k3s_server
  become: yes
  gather_facts: no
  tasks:
    - name: Join non-bootstrap servers to the control plane
      include_role:
        name: k3s_server_join
      when: inventory_hostname != k3s_bootstrap_host

# Play 4: validate cluster and export kubeconfig
- name: Validate cluster and export kubeconfig
  hosts: "{{ groups.get('role_k3s_server', ['localhost']) | sort | first }}"
  become: yes
  gather_facts: no
  roles:
    - k3s_postcheck
```

**Step 6 — Role details**

`k3s_prereqs/tasks/main.yml` — installs: curl, open-iscsi, nfs-common, apt-transport-https

`k3s_server_bootstrap/tasks/main.yml`:
1. Download k3s install script
2. Run with `INSTALL_K3S_EXEC="server --cluster-init"` (only on first node)
3. Wait for k3s to be ready (`kubectl get nodes`)
4. Read join token from `/var/lib/rancher/k3s/server/node-token`
5. Store token as Ansible fact for other plays

`k3s_server_join/tasks/main.yml`:
1. Run k3s install with `INSTALL_K3S_EXEC="server --server https://<first-node-ip>:6443"` and token
2. Wait for node to appear in `kubectl get nodes`

`k3s_postcheck/tasks/main.yml`:
1. Run `kubectl get nodes` and assert all 3 are Ready
2. Fetch `/etc/rancher/k3s/k3s.yaml` to local machine
3. Replace `127.0.0.1` in kubeconfig with the public IP of first node
4. Save as `~/.kube/config` locally (or a named context)

**Step 7 — Verify from local machine**

```bash
kubectl get nodes
kubectl get pods -A
```

All 3 nodes should appear as `Ready`.

**Step 8 — Install Headlamp (optional — bonus task)**

Headlamp is a Kubernetes UI. Install via Helm:

```bash
helm repo add headlamp https://headlamp-k8s.github.io/headlamp/
helm install headlamp headlamp/headlamp -n kube-system
```

Or via Ansible role `k3s_headlamp` using the `kubernetes.core.helm` module.

Result should look like Image 1 — Headlamp showing all workloads in the cluster.

---

## Task 3 — Ingress, TLS, Homepage, Headlamp

### Background

**What is Ingress?**
In Kubernetes, a Service exposes pods internally. Ingress is a layer on top that routes external HTTP/HTTPS traffic to the right service based on hostname or path. k3s ships with **Traefik** as the default Ingress controller — it's already running after k3s install.

**What is cert-manager?**
cert-manager automates TLS certificate management. It watches for `Certificate` resources and automatically requests/renews certificates from Let's Encrypt (or other CAs) using ACME DNS/HTTP challenge.

**What is Homepage?**
A lightweight dashboard (https://gethomepage.dev) — shows links to your services, status indicators, custom bookmarks. Good for showcasing all deployed services in one place.

### Step-by-Step

**Step 1 — cert-manager role**

Create `ansible/roles/cert_manager/`:
- Install via Helm: `helm install cert-manager jetstack/cert-manager --set installCRDs=true`
- Use `kubernetes.core.helm` Ansible module — not `shell`
- Create a `ClusterIssuer` resource pointing to Let's Encrypt

```yaml
# ansible/roles/cert_manager/tasks/main.yml
- name: Add jetstack Helm repo
  kubernetes.core.helm_repository:
    name: jetstack
    repo_url: https://charts.jetstack.io

- name: Install cert-manager
  kubernetes.core.helm:
    name: cert-manager
    chart_ref: jetstack/cert-manager
    release_namespace: cert-manager
    create_namespace: true
    values:
      installCRDs: true

- name: Create ClusterIssuer for Let's Encrypt
  kubernetes.core.k8s:
    definition: "{{ lookup('template', 'clusterissuer.yaml.j2') }}"
```

**Step 2 — Ingress role**

k3s ships Traefik automatically. If using built-in Traefik:
- Verify it's running: `kubectl get pods -n kube-system | grep traefik`
- Create a role `ingress_config` that applies Traefik IngressRoute or standard Ingress resources

If installing a different controller (Nginx):
```yaml
- name: Install nginx ingress
  kubernetes.core.helm:
    name: ingress-nginx
    chart_ref: ingress-nginx/ingress-nginx
    release_namespace: ingress-nginx
    create_namespace: true
```

**Step 3 — Homepage role**

Create `ansible/roles/k3s_homepage/`:
- Install via Helm or raw Kubernetes manifests
- Configure services.yaml and bookmarks.yaml via ConfigMap
- Create Ingress resource for it with TLS certificate

**Step 4 — Headlamp role**

Create `ansible/roles/k3s_headlamp/`:
- Install via `kubernetes.core.helm`
- Create Ingress with TLS

**Step 5 — Main playbook structure**

```yaml
# ansible/k3s-apps.yml
- name: Install cluster applications
  hosts: "{{ groups.get('role_k3s_server', ['localhost']) | sort | first }}"
  become: yes
  roles:
    - cert_manager
    - ingress_config
    - k3s_headlamp
    - k3s_homepage
```

**Step 6 — Verify**

```bash
kubectl get ingress -A
kubectl get certificate -A       # should show READY=True
kubectl get pods -A              # all Running
```

Access https://your-domain/headlamp and https://your-domain/ (Homepage).

---

## Key Principles (Mentor Feedback)

**On Ansible roles:**
- Extend existing roles, don't create parallel config from scratch
- Roles call other roles via `include_role` — avoids repeating common setup
- The more fragmented the roles, the less code duplication — this is a strong interview signal
- Example from screenshot: `k3s_cluster.yml` calls `k3s_server_bootstrap` which internally calls `k3s_server_join` via `include_role`

**On Kubernetes tooling in Ansible:**
- Use `kubernetes.core.helm` for Helm chart installs — not `shell: helm install ...`
- Use `kubernetes.core.k8s` for applying manifests — not `shell: kubectl apply -f ...`
- Avoid `shell` wherever a proper Ansible module exists

**On Tailscale:**
- One Tailscale node per network (subnet router pattern)
- `--advertise-routes` is the key flag
- Approve routes in the Tailscale admin panel after running

---

## Current Infrastructure State (After Destroy)

Azure and AWS resources were destroyed to stop credit usage. What exists:

| Cloud | What's there | State |
|-------|-------------|-------|
| Azure for Students | Service Principal terraform-sa, coinops-tfstate-rg, coinopspenina storage | Exists |
| AWS | All destroyed | Empty |
| GCP | devops-intern-penina project, SA, tf-state bucket | Exists |

For Task 2: GCP is used (already bootstrapped, no policy restrictions, consistent quota).

---

## Files to Create / Modify

```
ansible/
  roles/
    tailscale_gateway/
      tasks/main.yml          ← NEW (subnet router install)
      defaults/main.yml       ← NEW
    k3s_prereqs/
      tasks/main.yml          ← NEW
    k3s_server_bootstrap/
      tasks/main.yml          ← NEW
    k3s_server_join/
      tasks/main.yml          ← NEW
    k3s_postcheck/
      tasks/main.yml          ← NEW
    cert_manager/
      tasks/main.yml          ← NEW
      templates/
        clusterissuer.yaml.j2 ← NEW
    k3s_headlamp/
      tasks/main.yml          ← NEW
    k3s_homepage/
      tasks/main.yml          ← NEW
  inventory/
    inventory.gcp_compute.yml ← NEW or update existing
  k3s-cluster.yml             ← NEW playbook
  k3s-apps.yml                ← NEW playbook
  provision.yml               ← UPDATE (tailscale_gateway on jump_host only)

terraform/
  config.yaml                 ← UPDATE (add 3 GCP k3s VMs)
  modules/gcp_vm/main.tf      ← check k3s tags/firewall
  modules/gcp_security/main.tf ← UPDATE (add k3s ports)
```

---

## Resources

- k3s docs: https://docs.k3s.io/installation/requirements
- k3s HA server setup: https://docs.k3s.io/datastore/ha-embedded
- Tailscale subnet router: https://tailscale.com/kb/1019/subnets
- Headlamp: https://headlamp.dev
- Lens (alternative UI): https://lenshq.io
- Homepage dashboard: https://gethomepage.dev
- cert-manager: https://cert-manager.io/docs/installation/helm/
- kubernetes.core Ansible collection: https://docs.ansible.com/ansible/latest/collections/kubernetes/core/
