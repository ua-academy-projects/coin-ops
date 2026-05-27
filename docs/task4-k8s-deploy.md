# Task 4 — Deploy CoinOps Application to Kubernetes (k3s)

Branch: `dev-penina-cloud` | Owner: Marta Penina

---

## Goal

Deploy the full CoinOps application stack into the existing k3s cluster on GCP.
All services must run as Kubernetes workloads — not Docker Compose on raw VMs.

---

## Current State

- k3s cluster: 3 nodes Ready (k3s-server-1/2/3) ✅
- Traefik Ingress: running ✅
- cert-manager: running, Let's Encrypt ClusterIssuer ready ✅
- Homepage dashboard: running at `k3s.coinops-softserve-penina.pp.ua` ✅
- Headlamp UI: running at `headlamp.coinops-softserve-penina.pp.ua` ✅ (needs to be moved off public Ingress — see Issue below)

---

## What Needs To Be Done

### Fix 1 — Remove Headlamp from public Ingress

**Problem:** Headlamp is an admin tool — it should NOT be publicly accessible.
Exposing a cluster management UI on a public IP is a security anti-pattern, even with token auth.

**Correct approach:** Remove the Headlamp Ingress entirely. Access via `kubectl port-forward` only:
```bash
kubectl port-forward -n headlamp svc/headlamp 8080:80
# open localhost:8080 — only accessible to the engineer running this
```

This means Headlamp has no public exposure at all — ClusterIP service only.

**Why not NodePort?** NodePort opens a random high port on every node directly — bypasses Ingress, no TLS, not production practice. Mentor explicitly said: no NodePort.

---

### Main Task — Deploy CoinOps Services to k3s

Deploy all CoinOps services as Kubernetes Deployments with proper namespace isolation.

#### Services to deploy

| Service | Source image | Namespace |
|---------|-------------|-----------|
| UI (nginx + React) | ghcr.io/ua-academy-projects/coin-ops/ui | `coinops` |
| Proxy (Go) | ghcr.io/ua-academy-projects/coin-ops/proxy | `coinops` |
| History API | ghcr.io/ua-academy-projects/coin-ops/history | `coinops` |
| PostgreSQL | postgres:16 | `coinops` |
| RabbitMQ | rabbitmq:3-management | `coinops` (if external runtime) |
| Redis | redis:7 | `coinops` (if external runtime) |

> Note: if `RUNTIME_BACKEND=postgres` — RabbitMQ and Redis are not needed (pgmq handles queueing inside PostgreSQL).

#### Namespace strategy

Per mentor feedback — separate namespaces per concern:

```
coinops      ← application services (proxy, history, ui, db)
homepage     ← homepage dashboard (already exists)
headlamp     ← headlamp UI (already exists, access via port-forward only)
cert-manager ← TLS automation (already exists)
monitoring   ← future: Prometheus, Grafana (separate namespace)
logging      ← future: Loki, Promtail (separate namespace)
```

Do NOT put everything in `default` namespace.

---

## Architecture After This Task

```
Internet
  │
  ▼
34.158.238.181:443
  │
  ▼
Traefik Ingress
  │
  ├── coinops-softserve-penina.pp.ua  → UI service (namespace: coinops)
  └── k3s.coinops-softserve-penina.pp.ua → Homepage (namespace: homepage)

Internal only (no Ingress):
  └── Headlamp → kubectl port-forward only (namespace: headlamp)

coinops namespace:
  ├── Deployment: ui        → ClusterIP service
  ├── Deployment: proxy     → ClusterIP service
  ├── Deployment: history   → ClusterIP service
  ├── StatefulSet: postgres → ClusterIP service + PersistentVolumeClaim
  └── ConfigMap + Secrets   → env vars for all services
```

---

## Implementation Approach

### Ansible roles to create

Following the same pattern as existing roles:

```
ansible/roles/k3s_coinops/
  tasks/main.yml      ← creates namespace, deploys all services
  defaults/main.yml   ← image tags, domain, resource limits
  templates/          ← if any ConfigMap templates needed
```

### Key principles (from mentor)

- Use `kubernetes.core.k8s` for manifests — NOT `shell: kubectl apply`
- Use `kubernetes.core.helm` for Helm charts — NOT `shell: helm install`
- Separate namespaces per concern
- No NodePort — use ClusterIP + Ingress
- Secrets should come from environment variables via Ansible `lookup('env', ...)` — not hardcoded

### Playbook

Add to `ansible/k3s-apps.yml`:
```yaml
- name: Deploy CoinOps application
  hosts: k3s_bootstrap
  become: yes
  environment:
    KUBECONFIG: /etc/rancher/k3s/k3s.yaml
  roles:
    - k3s_coinops
```

---

## Ingress for CoinOps UI

```yaml
# Routes coinops-softserve-penina.pp.ua to the UI service
kind: Ingress
metadata:
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  ingressClassName: traefik
  rules:
    - host: coinops-softserve-penina.pp.ua
      http:
        paths:
          - path: /
            backend:
              service:
                name: ui
                port:
                  number: 80
  tls:
    - hosts:
        - coinops-softserve-penina.pp.ua
      secretName: coinops-ui-tls
```

---

## DNS

Update Cloudflare DNS record:
```
coinops-softserve-penina.pp.ua  A  34.158.238.181  (Proxied)
```
This currently points to Azure LB (20.91.139.85) — update to k3s public IP.

---

## Problems To Expect

**Image pull from GHCR** — images may be private. Need `imagePullSecret` with GHCR credentials.

**PostgreSQL persistence** — needs PersistentVolumeClaim. `local-path-provisioner` is already in the cluster and can handle this.

**Inter-service communication** — services communicate via Kubernetes DNS:
```
proxy → history-api.coinops.svc.cluster.local
proxy → postgres.coinops.svc.cluster.local
```

**Environment variables** — DB passwords, API keys must come from Kubernetes Secrets, not ConfigMaps.

---

## Success Criteria

```bash
kubectl get pods -n coinops
# All pods Running

kubectl get ingress -n coinops
# coinops-softserve-penina.pp.ua → ui service

# Browser:
# https://coinops-softserve-penina.pp.ua → CoinOps app
# https://k3s.coinops-softserve-penina.pp.ua → Homepage
# headlamp → only via kubectl port-forward (no public URL)
```
