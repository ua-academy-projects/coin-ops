# Task 2 + Task 3 — k3s Cluster on GCP + Ingress + TLS + Apps

Branch: `dev-penina-cloud`

---

## Overview

| Task | What | Time |
|------|------|------|
| Task 2 | k3s cluster on GCP (3 nodes via Terraform + Ansible) | ~4-5 hrs |
| Task 3 | Ingress + TLS + Homepage + Headlamp on k3s | ~2-3 hrs |
| **Total** | | **~6-8 hrs** |

---

## Task 2 — k3s Cluster on GCP

### What is k3s?

k3s is a lightweight Kubernetes distribution that fits in a single binary under 100MB.
Full Kubernetes needs 8+ GB RAM per node. k3s runs on 2GB minimum.
Designed for edge, IoT, and learning environments.

### Control plane vs worker — our case

In production clusters these are separate:
- **Server (control plane)** — runs API server, scheduler, etcd. Accepts `kubectl` commands.
- **Agent (worker)** — runs actual pods/containers.

In our 3-node cluster: **all 3 nodes are server+worker** (combined). Simpler, fine for learning.

### k3s bootstrap sequence

```
Node 1: k3s server --cluster-init    ← initializes cluster, creates token
Node 2: k3s server --server https://node1:6443 --token <token>  ← joins
Node 3: k3s server --server https://node1:6443 --token <token>  ← joins
```

---

## Task 2 — Step by Step

### Step 1 — Terraform: add 3 GCP VMs to config.yaml

```yaml
# terraform/config.yaml — add to vms section
k3s-server-1:
  cloud: "gcp"
  size: medium       # e2-small = 2vCPU 2GB, e2-medium = 2vCPU 4GB
  zone: primary
  tags: ["k3s-server"]
  public_ip: true    # entry point for kubectl and SSH

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

Also add `gateway-gcp` for Tailscale subnet router (same pattern as AWS/Azure):
```yaml
gateway-gcp:
  cloud: "gcp"
  size: small
  zone: primary
  tags: ["gateway"]
  public_ip: true
```

### Step 2 — GCP firewall rules

Add to `terraform/modules/gcp_security/main.tf`:

```hcl
resource "google_compute_firewall" "k3s" {
  name    = "k3s-firewall"
  network = var.vpc_name

  allow { protocol = "tcp"; ports = ["6443"] }   # Kubernetes API
  allow { protocol = "tcp"; ports = ["9345"] }   # k3s supervisor API
  allow { protocol = "tcp"; ports = ["2379-2380"] } # etcd
  allow { protocol = "udp"; ports = ["8472"] }   # Flannel VXLAN
  allow { protocol = "tcp"; ports = ["10250"] }  # kubelet

  source_ranges = ["10.0.0.0/8"]   # only internal traffic
  target_tags   = ["k3s-server"]
}
```

### Step 3 — terraform apply

```bash
cd terraform
terraform plan
terraform apply -auto-approve
terraform output  # get GCP VM IPs
```

### Step 4 — Update ansible/inventory

Add new groups:

```ini
[k3s_bootstrap]
k3s-server-1  ansible_host=<public-ip>

[k3s_join]
k3s-server-2  ansible_host=<private-ip>
k3s-server-3  ansible_host=<private-ip>

[k3s_server:children]
k3s_bootstrap
k3s_join

[k3s_join:vars]
ansible_ssh_common_args=-o ProxyJump=marta_ops@<k3s-server-1-ip>:9922 -o StrictHostKeyChecking=no
```

### Step 5 — Create Ansible roles

```
ansible/roles/
  k3s_prereqs/
    tasks/main.yml    ← install curl, open-iscsi, nfs-common
  k3s_server_bootstrap/
    tasks/main.yml    ← init cluster on node 1, save token
    defaults/main.yml
  k3s_server_join/
    tasks/main.yml    ← join nodes 2+3 using token from bootstrap
    defaults/main.yml
  k3s_postcheck/
    tasks/main.yml    ← verify cluster, fetch kubeconfig locally
```

**k3s_prereqs/tasks/main.yml:**
```yaml
- name: Install k3s prerequisites
  apt:
    name:
      - curl
      - open-iscsi
      - nfs-common
      - apt-transport-https
    state: present
    update_cache: yes
```

**k3s_server_bootstrap/tasks/main.yml:**
```yaml
- name: Download k3s install script
  get_url:
    url: https://get.k3s.io
    dest: /tmp/k3s-install.sh
    mode: '0755'

- name: Install and init k3s cluster (first node only)
  shell: INSTALL_K3S_EXEC="server --cluster-init" /tmp/k3s-install.sh
  environment:
    INSTALL_K3S_VERSION: "v1.31.0+k3s1"

- name: Wait for k3s to be ready
  wait_for:
    port: 6443
    timeout: 120

- name: Read node join token
  slurp:
    src: /var/lib/rancher/k3s/server/node-token
  register: k3s_token_raw

- name: Set token fact for other plays
  set_fact:
    k3s_token: "{{ k3s_token_raw.content | b64decode | trim }}"
    k3s_server_ip: "{{ ansible_default_ipv4.address }}"
```

**k3s_server_join/tasks/main.yml:**
```yaml
- name: Download k3s install script
  get_url:
    url: https://get.k3s.io
    dest: /tmp/k3s-install.sh
    mode: '0755'

- name: Join k3s cluster
  shell: >
    INSTALL_K3S_EXEC="server --server https://{{ k3s_server_ip }}:6443"
    K3S_TOKEN="{{ k3s_token }}"
    /tmp/k3s-install.sh
  environment:
    INSTALL_K3S_VERSION: "v1.31.0+k3s1"

- name: Wait for node to be ready
  command: kubectl get node {{ inventory_hostname }}
  retries: 12
  delay: 10
  register: result
  until: "'Ready' in result.stdout"
```

**k3s_postcheck/tasks/main.yml:**
```yaml
- name: Verify all nodes are Ready
  command: kubectl get nodes
  register: nodes_output
  changed_when: false

- name: Show cluster status
  debug:
    msg: "{{ nodes_output.stdout_lines }}"

- name: Fetch kubeconfig
  fetch:
    src: /etc/rancher/k3s/k3s.yaml
    dest: /tmp/k3s-config.yaml
    flat: yes

- name: Replace 127.0.0.1 with public IP in kubeconfig
  replace:
    path: /tmp/k3s-config.yaml
    regexp: '127\.0\.0\.1'
    replace: "{{ ansible_host }}"
  delegate_to: localhost
```

### Step 6 — Create ansible/k3s-cluster.yml playbook

```yaml
---
- name: Prepare all k3s nodes
  hosts: k3s_server
  become: yes
  roles:
    - common
    - k3s_prereqs

- name: Bootstrap first k3s server
  hosts: k3s_bootstrap
  become: yes
  roles:
    - k3s_server_bootstrap

- name: Join remaining k3s servers
  hosts: k3s_join
  become: yes
  roles:
    - k3s_server_join

- name: Validate cluster and fetch kubeconfig
  hosts: k3s_bootstrap
  become: yes
  roles:
    - k3s_postcheck
```

### Step 7 — Run and verify

```bash
# On jump-host or locally if GCP nodes are reachable
ansible-playbook -i ansible/inventory ansible/k3s-cluster.yml

# Verify locally
export KUBECONFIG=/tmp/k3s-config.yaml
kubectl get nodes
# Expected:
# NAME           STATUS   ROLES                       AGE
# k3s-server-1   Ready    control-plane,etcd,master   5m
# k3s-server-2   Ready    control-plane,etcd,master   3m
# k3s-server-3   Ready    control-plane,etcd,master   2m
```

---

## Task 3 — Ingress + TLS + Apps

### What is Ingress?

Service = exposes pods internally in the cluster.
Ingress = routes external HTTP/HTTPS traffic to the right service based on hostname or path.
k3s ships **Traefik** as default Ingress controller — already running after install.

### What is cert-manager?

Automates TLS certificate management. Watches for `Certificate` resources and requests certificates from Let's Encrypt automatically. No manual certificate renewal.

### Step 1 — Create ansible/roles/cert_manager/

```
ansible/roles/cert_manager/
  tasks/main.yml
  templates/
    clusterissuer.yaml.j2
```

**tasks/main.yml:**
```yaml
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

- name: Wait for cert-manager pods
  kubernetes.core.k8s_info:
    kind: Pod
    namespace: cert-manager
    label_selectors:
      - app.kubernetes.io/name=cert-manager
    wait: yes
    wait_condition:
      type: Ready
      status: "True"

- name: Create ClusterIssuer for Let's Encrypt
  kubernetes.core.k8s:
    definition: "{{ lookup('template', 'clusterissuer.yaml.j2') }}"
```

**templates/clusterissuer.yaml.j2:**
```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: marta.penina.academic@gmail.com
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
      - http01:
          ingress:
            class: traefik
```

### Step 2 — Create ansible/roles/k3s_headlamp/

Headlamp = Kubernetes UI dashboard.

```yaml
# tasks/main.yml
- name: Add headlamp Helm repo
  kubernetes.core.helm_repository:
    name: headlamp
    repo_url: https://headlamp-k8s.github.io/headlamp/

- name: Install Headlamp
  kubernetes.core.helm:
    name: headlamp
    chart_ref: headlamp/headlamp
    release_namespace: kube-system
    values:
      ingress:
        enabled: true
        hosts:
          - host: "headlamp.{{ app_domain }}"
            paths:
              - path: /
                type: Prefix
        tls:
          - secretName: headlamp-tls
            hosts:
              - "headlamp.{{ app_domain }}"
        annotations:
          cert-manager.io/cluster-issuer: letsencrypt-prod
```

### Step 3 — Create ansible/roles/k3s_homepage/

Homepage = simple dashboard showing all your services.

```yaml
# tasks/main.yml
- name: Add homepage Helm repo
  kubernetes.core.helm_repository:
    name: jameswynn
    repo_url: https://jameswynn.github.io/helm-charts

- name: Install Homepage
  kubernetes.core.helm:
    name: homepage
    chart_ref: jameswynn/homepage
    release_namespace: default
    values:
      ingress:
        main:
          enabled: true
          hosts:
            - host: "{{ app_domain }}"
              paths:
                - path: /
                  pathType: Prefix
          tls:
            - secretName: homepage-tls
              hosts:
                - "{{ app_domain }}"
          annotations:
            cert-manager.io/cluster-issuer: letsencrypt-prod
```

### Step 4 — Create ansible/k3s-apps.yml playbook

```yaml
---
- name: Install cluster applications
  hosts: k3s_bootstrap
  become: yes
  vars:
    app_domain: coinops-softserve-penina.pp.ua
  roles:
    - cert_manager
    - k3s_headlamp
    - k3s_homepage
```

### Step 5 — DNS update in Cloudflare

After apps are deployed, point the domain to k3s-server-1 public IP:

```
A  coinops-softserve-penina.pp.ua     → <k3s-server-1-public-ip>  (Proxied)
A  headlamp.coinops-softserve-penina.pp.ua → <k3s-server-1-public-ip>  (Proxied)
```

### Step 6 — Verify

```bash
kubectl get ingress -A
kubectl get certificate -A      # READY=True means TLS works
kubectl get pods -A             # all Running
```

Access:
- `https://coinops-softserve-penina.pp.ua` — Homepage dashboard
- `https://headlamp.coinops-softserve-penina.pp.ua` — Headlamp Kubernetes UI

---

## Files to Create / Modify

```
terraform/
  config.yaml                        ← add k3s-server-1/2/3, gateway-gcp
  modules/gcp_security/main.tf       ← add k3s firewall rules

ansible/
  inventory                          ← add k3s_bootstrap, k3s_join, k3s_server groups
  k3s-cluster.yml                    ← NEW playbook
  k3s-apps.yml                       ← NEW playbook
  roles/
    k3s_prereqs/tasks/main.yml       ← NEW
    k3s_server_bootstrap/
      tasks/main.yml                 ← NEW
      defaults/main.yml              ← NEW
    k3s_server_join/
      tasks/main.yml                 ← NEW
      defaults/main.yml              ← NEW
    k3s_postcheck/
      tasks/main.yml                 ← NEW
    cert_manager/
      tasks/main.yml                 ← NEW
      templates/clusterissuer.yaml.j2 ← NEW
    k3s_headlamp/
      tasks/main.yml                 ← NEW
    k3s_homepage/
      tasks/main.yml                 ← NEW
```

---

## Key Principles (from mentor notes)

- Use `kubernetes.core.helm` — not `shell: helm install`
- Use `kubernetes.core.k8s` for manifests — not `shell: kubectl apply`
- Roles call roles via `include_role` — avoids duplication
- `k3s_server_bootstrap` runs only on node 1 — `k3s_server_join` on nodes 2+3
- All 3 nodes = server+worker (no role separation needed for this scale)
