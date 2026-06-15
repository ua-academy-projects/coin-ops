# Repository Guidelines

## Project Structure

This repository contains the CoinOps application and the Ansible automation that
deploys it to k3s.

Current layout:

- `ui-react/` - React/Vite frontend
- `proxy/` - Go live-data proxy
- `history/` - FastAPI history API, RabbitMQ consumer, PostgreSQL schema
- `runtime/` - PostgreSQL runtime queue/session assets for future work
- `ansible/` - k3s cluster, platform, and CoinOps Kubernetes deployment
- `charts/coinops/` - local Helm chart for the CoinOps application layer
- `tests/` - Python unit and integration tests
- `docs/` - current k3s and application runbooks

Keep deployment work focused on the current k3s and Kubernetes path.

## Development Commands

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
pip install -r requirements.txt -r requirements-dev.txt
python main.py
python consumer.py
```

Python tests from the repository root:

```bash
python -m pytest tests/python/unit -v
python -m pytest tests/python/integration -v
```

## k3s Deployment Commands

Install Ansible collections:

```bash
ansible-galaxy collection install -r ansible/requirements.yml
```

Deploy the application:

```bash
ansible-playbook -i ansible/inventory.k3s.gcp ansible/coinops-app.yml
```

Use tags for targeted changes:

```bash
ansible-playbook -i ansible/inventory.k3s.gcp ansible/coinops-app.yml --tags data
ansible-playbook -i ansible/inventory.k3s.gcp ansible/coinops-app.yml --tags app
```

The application layer is packaged as a local Helm chart at `charts/coinops/`
and installed by the `coinops_app_chart` role as the `coinops` Helm release.
The chart deploys: proxy Deployment + Service, history API Deployment + Service,
history consumer Deployment, UI Deployment + Service, frontend and backend
Ingresses, and two Traefik strip-prefix middlewares.

The data layer (PostgreSQL via CNPG, RabbitMQ, Redis, all secrets) stays in
the `coinops_data` role and is intentionally outside the chart.

## Coding Style

Use TypeScript for React UI code and keep components in `ui-react/src/`. Go
code must be formatted with `gofmt`. Python code should use clear snake_case
names and keep API and consumer responsibilities separated.

YAML files use two-space indentation. Ansible role variables should live in
`roles/<role>/defaults/main.yml` and start with the role name, for example
`coinops_data_*` and `coinops_app_chart_*`.

Helm chart templates live in `charts/coinops/templates/`, grouped by component
(`proxy/`, `history/`, `ui/`, `ingress/`). Common label, selector, and image
helpers are defined in `templates/_helpers.tpl` and reused via `include`.
Chart values are validated against `charts/coinops/values.schema.json`; run
`helm lint ./charts/coinops` before committing chart changes.

## Security

Never commit real credentials. Secrets live in GCP Secret Manager and are
copied into Kubernetes Secrets by Ansible.

Do not commit:

- kubeconfig files
- Headlamp tokens
- GHCR tokens
- Cloudflare API tokens
- SSH private keys
- GCP service account JSON files
- `.env` files with real values

## Architecture Notes

The production-style path is:

```text
Browser -> Cloudflare DNS -> GCP L4 Load Balancer -> Traefik -> Ingress -> Services -> Pods
```

The frontend should keep same-origin paths:

- `/api`
- `/history-api`

The browser should not call internal service DNS names or node IPs directly.
