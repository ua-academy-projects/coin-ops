# CoinOps On k3s

This document describes the Kubernetes deployment of the real CoinOps
application on the GCP k3s cluster.

The application is publicly available at:

```text
https://coinops.kazachuk-k3s.pp.ua/
```

## Final Architecture

```text
Browser
  |
  v
Cloudflare DNS
  coinops.kazachuk-k3s.pp.ua -> 34.133.206.188
  |
  v
GCP L4 Load Balancer
  forwards TCP 80/443 to k3s nodes
  |
  v
k3s Traefik ingress controller
  terminates HTTPS with cert-manager certificate
  |
  v
Kubernetes Ingress
  /             -> coinops-ui
  /api          -> coinops-proxy
  /history-api  -> coinops-history-api
```

Internal application dependencies:

```text
coinops-ui
  |
  +-- /api ---------> coinops-proxy
  |                    |
  |                    +-- Redis
  |                    +-- RabbitMQ
  |
  +-- /history-api --> coinops-history-api
                       |
                       +-- CNPG PostgreSQL

coinops-history-consumer
  |
  +-- RabbitMQ
  +-- CNPG PostgreSQL
```

## Namespaces

The app is intentionally split across namespaces instead of placing everything
into `default`.

| Namespace | Purpose |
| --- | --- |
| `cnpg-system` | CNPG operator |
| `coinops-data` | PostgreSQL, RabbitMQ, Redis, data secrets |
| `coinops-backend` | Proxy, history API, history consumer |
| `coinops-frontend` | React UI and public TLS certificate |

## Ansible Entry Point

Main playbook:

```text
ansible/coinops-app.yml
```

Run everything:

```bash
ANSIBLE_LOCAL_TEMP=/private/tmp/coin-ops-ansible-tmp \
ANSIBLE_REMOTE_TEMP=/tmp/coin-ops-ansible-tmp \
ANSIBLE_SSH_CONTROL_PATH_DIR=/private/tmp/coin-ops-ansible-cp \
ansible-playbook -i ansible/inventory.k3s.gcp ansible/coinops-app.yml
```

Run only one layer:

```bash
ansible-playbook -i ansible/inventory.k3s.gcp ansible/coinops-app.yml --tags cnpg
ansible-playbook -i ansible/inventory.k3s.gcp ansible/coinops-app.yml --tags data
ansible-playbook -i ansible/inventory.k3s.gcp ansible/coinops-app.yml --tags app
```

Tags are used because each layer has a different lifecycle. For example,
changing the app should not reinstall PostgreSQL.

The legacy tags `backend`, `frontend`, `ingress`, `proxy`, `history`, and `ui`
are still accepted; each of them runs `helm upgrade` on the full `coinops`
release.

## Role Map

| Role | What it does |
| --- | --- |
| `cnpg_operator` | Installs the CloudNativePG operator with Helm |
| `coinops_data` | Creates namespaces, reads GCP secrets, creates Kubernetes secrets, creates PostgreSQL, installs RabbitMQ and Redis |
| `coinops_app_chart` | Installs the CoinOps application Helm chart from `charts/coinops/` (proxy, history API, history consumer, UI, public Ingress, Traefik strip-prefix middlewares) |

All role variables live in `roles/<role>/defaults/main.yml` and are prefixed
with the role name, for example `coinops_data_*` and `coinops_app_chart_*`.

## Why Helm Is Used

Helm is a package manager for Kubernetes. It is used both for third-party
software that already has a chart and to package the CoinOps application
itself.

Helm releases in this deployment:

| Release | Namespace | Source |
| --- | --- | --- |
| `cnpg` | `cnpg-system` | upstream chart |
| `rabbitmq` | `coinops-data` | upstream Bitnami chart |
| `redis` | `coinops-data` | upstream Bitnami chart |
| `coinops` | `coinops-backend` | local chart in `charts/coinops/` |

The local CoinOps chart deploys the application layer only (proxy, history API,
history consumer, UI, ingress + middlewares). The data layer (PostgreSQL,
RabbitMQ, Redis, secrets) stays outside the chart because it has a different
lifecycle and is provisioned by `coinops_data`.

## Why CNPG Is Used

CNPG means CloudNativePG. It is a Kubernetes operator for PostgreSQL.

Instead of manually creating one PostgreSQL container, CNPG manages PostgreSQL
as a Kubernetes-native database cluster:

- creates PostgreSQL pods
- creates services such as `coinops-postgres-rw`
- manages primary/replica behavior
- exposes database status through Kubernetes CRDs

Current cluster:

```text
coinops-postgres
  instances: 3
  database: cognitor
  owner: coinops
  service: coinops-postgres-rw.coinops-data.svc
```

## Secrets

Source of truth for sensitive values is GCP Secret Manager.

Expected GCP secrets:

| Secret | Expected keys |
| --- | --- |
| `coinops-db-secrets` | `db_user`, `db_password`, `db_name` |
| `coinops-service-secrets` | `rabbitmq_user`, `rabbitmq_password`, `redis_password`, `ghcr_username`, `ghcr_token` |
| `cloudflare-api-token` | Cloudflare API token used by cert-manager issuer |

Ansible reads these values and creates Kubernetes Secrets:

| Kubernetes Secret | Namespace | Purpose |
| --- | --- | --- |
| `coinops-postgres-app-creds` | `coinops-data` | CNPG application user |
| `coinops-rabbitmq-creds` | `coinops-data` | RabbitMQ password |
| `coinops-redis-creds` | `coinops-data` | Redis password |
| `coinops-backend-env` | `coinops-backend` | `DATABASE_URL`, `RABBITMQ_URL`, `REDIS_URL` |
| `ghcr-pull-secret` | `coinops-backend`, `coinops-frontend` | Pull private GHCR images |
| `coinops-tls` | `coinops-frontend` | HTTPS certificate private key and cert |

Do not commit real secret values, kubeconfig files, or tokens.

## Public DNS And TLS

Cloudflare DNS record:

```text
Type: A
Name: coinops
Value: 34.133.206.188
Proxy: DNS only
```

The TLS certificate is issued by cert-manager using Cloudflare DNS-01. That
means Let's Encrypt validation happens by creating temporary DNS records through
the Cloudflare API, not by exposing an HTTP challenge endpoint.

Check certificate:

```bash
kubectl -n coinops-frontend get certificate
kubectl -n coinops-frontend describe certificate coinops-tls
kubectl -n coinops-frontend get secret coinops-tls
```

## Verification Commands

DNS:

```bash
dig @1.1.1.1 coinops.kazachuk-k3s.pp.ua +short
```

Expected:

```text
34.133.206.188
```

Pods:

```bash
kubectl -n cnpg-system get pods
kubectl -n coinops-data get pods
kubectl -n coinops-backend get pods
kubectl -n coinops-frontend get pods
```

Ingress and certificate:

```bash
kubectl -n coinops-frontend get ingress
kubectl -n coinops-backend get ingress
kubectl -n coinops-frontend get certificate
```

HTTP checks:

```bash
curl -I https://coinops.kazachuk-k3s.pp.ua/
curl -I https://coinops.kazachuk-k3s.pp.ua/api/health
curl -I https://coinops.kazachuk-k3s.pp.ua/history-api/health
```

Logs:

```bash
kubectl -n coinops-backend logs deployment/coinops-proxy --tail=100
kubectl -n coinops-backend logs deployment/coinops-history-api --tail=100
kubectl -n coinops-backend logs deployment/coinops-history-consumer --tail=100
kubectl -n coinops-frontend logs deployment/coinops-ui --tail=100
```

CNPG:

```bash
kubectl -n coinops-data get cluster
kubectl -n coinops-data get pods -l cnpg.io/cluster=coinops-postgres
kubectl -n coinops-data get svc | grep coinops-postgres
```

Helm releases:

```bash
helm -n cnpg-system list
helm -n coinops-data list
```

## Files To Show In Review

| File | Why it matters |
| --- | --- |
| `ansible/coinops-app.yml` | Shows the deployment order and tags |
| `ansible/roles/cnpg_operator/defaults/main.yml` | CNPG Helm chart config |
| `ansible/roles/coinops_data/tasks/main.yml` | Secrets, namespaces, CNPG, RabbitMQ, Redis |
| `ansible/roles/coinops_data/templates/postgres-cluster.yml.j2` | PostgreSQL cluster CR |
| `ansible/roles/coinops_app_chart/tasks/main.yml` | Calls `helm install/upgrade` for the app chart |
| `charts/coinops/Chart.yaml` | Helm chart metadata |
| `charts/coinops/values.yaml` | Default values for the app chart |
| `charts/coinops/values.schema.json` | JSON Schema validation for values |
| `charts/coinops/templates/_helpers.tpl` | Shared label / selector / image helpers |
| `charts/coinops/templates/proxy/` | Go proxy Deployment + Service |
| `charts/coinops/templates/history/` | History API Deployment + Service, history consumer Deployment |
| `charts/coinops/templates/ui/` | React UI Deployment + Service |
| `charts/coinops/templates/ingress/` | Frontend and backend Ingress, strip-prefix middlewares |

## Known Notes

- The GCP load balancer is L4. TLS is terminated inside Kubernetes by Traefik
  using the cert-manager certificate.
- Headlamp is not exposed publicly. It remains accessible through local
  `kubectl port-forward`.
- RabbitMQ and Redis are installed with Bitnami charts. Their images are pinned
  to `bitnamilegacy/*` because the chart-selected Docker Hub image tags were not
  available in the current registry path during deployment.
- The app still uses the `external` runtime mode: RabbitMQ and Redis remain
  part of the running application path.

## Current Status

Working:

- GCP Load Balancer routes traffic to k3s nodes
- Traefik routes public traffic by host and path
- cert-manager issued a production Let's Encrypt certificate
- CoinOps UI is reachable by HTTPS
- proxy, history API, history consumer, PostgreSQL, RabbitMQ, and Redis are
  running inside Kubernetes
