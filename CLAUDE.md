# CoinOps Project Context

CoinOps is deployed on a self-managed k3s cluster in GCP.

## Current Runtime Architecture

```text
Browser
  -> Cloudflare DNS
  -> GCP L4 Load Balancer
  -> k3s Traefik
  -> Kubernetes Ingress
  -> Services
  -> Pods
```

Public endpoint:

```text
https://coinops.kazachuk-k3s.pp.ua/
```

Ingress routes:

- `/` -> `coinops-ui`
- `/api` -> `coinops-proxy`
- `/history-api` -> `coinops-history-api`

## Application Services

| Path | Service |
| --- | --- |
| `ui-react/` | React/Vite UI |
| `proxy/` | Go live-data proxy |
| `history/main.py` | FastAPI history API |
| `history/consumer.py` | RabbitMQ consumer writing snapshots to PostgreSQL |
| `runtime/` | PostgreSQL runtime queue/session assets for future work |

## Kubernetes Namespaces

| Namespace | Purpose |
| --- | --- |
| `cnpg-system` | CNPG operator |
| `coinops-data` | PostgreSQL, RabbitMQ, Redis, data secrets |
| `coinops-backend` | proxy, history API, history consumer |
| `coinops-frontend` | UI, frontend Ingress, TLS Secret |

## Ansible

Main playbooks:

- `ansible/k3s-cluster.yml` - bootstraps the 3-node k3s cluster
- `ansible/k3s-platform.yml` - installs platform components
- `ansible/coinops-app.yml` - deploys the CoinOps app

Use tags for targeted app deployment:

```bash
ansible-playbook -i ansible/inventory.k3s.gcp ansible/coinops-app.yml --tags data
ansible-playbook -i ansible/inventory.k3s.gcp ansible/coinops-app.yml --tags app
```

The application layer (proxy, history API, history consumer, UI, public
Ingress, Traefik middlewares) is packaged as a local Helm chart at
`charts/coinops/` and installed by the `coinops_app_chart` role. The chart is
deployed as the `coinops` Helm release in the `coinops-backend` namespace.

The legacy tags `backend`, `frontend`, `ingress`, `proxy`, `history`, and `ui`
are still accepted but each runs `helm upgrade` on the full release.

## Secrets

Secrets are stored in GCP Secret Manager and copied into Kubernetes Secrets by
Ansible. Do not commit real token or password values.

Expected GCP Secret Manager records:

- `cloudflare-api-token`
- `coinops-db-secrets`
- `coinops-service-secrets`

## Useful Checks

```bash
kubectl get nodes -o wide
kubectl -n coinops-data get pods
kubectl -n coinops-backend get pods
kubectl -n coinops-frontend get pods
kubectl -n coinops-frontend get certificate
curl -I https://coinops.kazachuk-k3s.pp.ua/
```
