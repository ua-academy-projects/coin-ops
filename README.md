# CoinOps

CoinOps is a Polymarket intelligence dashboard deployed on a self-managed k3s
cluster in GCP.

The repository contains the application code, Kubernetes automation, tests, and
current documentation.

## Current Public Endpoint

```text
https://coinops.kazachuk-k3s.pp.ua/
```

## Current Architecture

```text
Browser
  |
  v
Cloudflare DNS
  coinops.kazachuk-k3s.pp.ua -> GCP Load Balancer IP
  |
  v
GCP L4 Load Balancer
  |
  v
k3s nodes
  |
  v
Traefik Ingress
  |
  +-- /             -> coinops-ui
  +-- /api          -> coinops-proxy
  +-- /history-api  -> coinops-history-api

coinops-proxy
  +-- Redis
  +-- RabbitMQ

coinops-history-consumer
  +-- RabbitMQ
  +-- CNPG PostgreSQL

coinops-history-api
  +-- CNPG PostgreSQL
```

## Repository Layout

```text
.
|-- .github/       # CI workflows for tests and container image publishing
|-- ansible/       # k3s cluster, platform, and CoinOps Kubernetes deployment
|-- docs/          # current architecture and runbooks
|-- history/       # FastAPI history API, RabbitMQ consumer, schema
|-- proxy/         # Go live-data proxy
|-- runtime/       # PostgreSQL runtime queue/session assets for future work
|-- tests/         # Python unit and integration tests
`-- ui-react/      # React/Vite frontend
```

## Main Runtime Components

| Layer | Component |
| --- | --- |
| Frontend | React, Vite, nginx container |
| Live gateway | Go proxy |
| History API | Python, FastAPI |
| Async ingestion | RabbitMQ and Python consumer |
| Database | PostgreSQL managed by CloudNativePG |
| Session state | Redis |
| Ingress | k3s Traefik |
| TLS | cert-manager with Cloudflare DNS-01 |
| Secrets | GCP Secret Manager -> Kubernetes Secrets |
| Deployment automation | Ansible Kubernetes modules and Helm modules |

## Container Images

GitHub Actions publishes service images to GHCR.

| Service | Image |
| --- | --- |
| Proxy | `ghcr.io/ua-academy-projects/coin-ops-proxy:dev-latest` |
| History API | `ghcr.io/ua-academy-projects/coin-ops-history-api:dev-latest` |
| History consumer | `ghcr.io/ua-academy-projects/coin-ops-history-consumer:dev-latest` |
| UI | `ghcr.io/ua-academy-projects/coin-ops-ui:dev-latest` |

## k3s Cluster Automation

The GCP VM infrastructure is created in the separate
`gcp-terraform-bootstrap` repository. This repository owns the Ansible
automation that configures k3s and deploys the application.

Cluster playbook:

```bash
ANSIBLE_LOCAL_TEMP=/private/tmp/coin-ops-ansible-tmp \
ANSIBLE_REMOTE_TEMP=/tmp/coin-ops-ansible-tmp \
ANSIBLE_SSH_CONTROL_PATH_DIR=/private/tmp/coin-ops-ansible-cp \
ansible-playbook -i ansible/inventory.k3s.gcp ansible/k3s-cluster.yml
```

Platform playbook:

```bash
ANSIBLE_LOCAL_TEMP=/private/tmp/coin-ops-ansible-tmp \
ANSIBLE_REMOTE_TEMP=/tmp/coin-ops-ansible-tmp \
ANSIBLE_SSH_CONTROL_PATH_DIR=/private/tmp/coin-ops-ansible-cp \
ansible-playbook -i ansible/inventory.k3s.gcp ansible/k3s-platform.yml
```

CoinOps app playbook:

```bash
ANSIBLE_LOCAL_TEMP=/private/tmp/coin-ops-ansible-tmp \
ANSIBLE_REMOTE_TEMP=/tmp/coin-ops-ansible-tmp \
ANSIBLE_SSH_CONTROL_PATH_DIR=/private/tmp/coin-ops-ansible-cp \
ansible-playbook -i ansible/inventory.k3s.gcp ansible/coinops-app.yml
```

Targeted app runs:

```bash
ansible-playbook -i ansible/inventory.k3s.gcp ansible/coinops-app.yml --tags cnpg
ansible-playbook -i ansible/inventory.k3s.gcp ansible/coinops-app.yml --tags data
ansible-playbook -i ansible/inventory.k3s.gcp ansible/coinops-app.yml --tags backend
ansible-playbook -i ansible/inventory.k3s.gcp ansible/coinops-app.yml --tags frontend
ansible-playbook -i ansible/inventory.k3s.gcp ansible/coinops-app.yml --tags ingress
```

## Useful Kubernetes Checks

```bash
kubectl get nodes -o wide
kubectl -n cnpg-system get pods
kubectl -n coinops-postgres get pods
kubectl -n coinops-rabbitmq get pods
kubectl -n coinops-redis get pods
kubectl -n coinops-backend get pods
kubectl -n coinops-frontend get pods
kubectl -n coinops-frontend get certificate
kubectl -n coinops-backend get ingress
```

External checks:

```bash
dig @1.1.1.1 coinops.kazachuk-k3s.pp.ua +short
curl -I https://coinops.kazachuk-k3s.pp.ua/
curl -I https://coinops.kazachuk-k3s.pp.ua/api/health
curl -I https://coinops.kazachuk-k3s.pp.ua/history-api/health
```

## Local Development

Frontend:

```bash
cd ui-react
npm install
npm run dev
npm run lint
npm run build
```

Go proxy:

```bash
cd proxy
make run
make build
go test ./...
```

Python history services:

```bash
cd history
python -m venv venv
source venv/bin/activate
pip install -r requirements.txt -r requirements-dev.txt
python main.py
python consumer.py
```

Python tests:

```bash
python -m pytest tests/python/unit -v
python -m pytest tests/python/integration -v
```

## Documentation

- [Architecture](docs/architecture.md)
- [k3s Cluster Runbook](docs/k3s-cluster.md)
- [CoinOps on k3s Runbook](docs/coinops-k3s-deployment.md)
- [Release Automation](docs/release-automation.md)

## Secrets

Do not commit secrets. Sensitive values live in GCP Secret Manager and are
projected into Kubernetes by Ansible.

Current expected GCP secrets:

- `cloudflare-api-token`
- `coinops-db-secrets`
- `coinops-service-secrets`

Never commit kubeconfig files, Headlamp tokens, GHCR tokens, Cloudflare tokens,
SSH private keys, GCP service account JSON files, or `.env` files with real
values.
