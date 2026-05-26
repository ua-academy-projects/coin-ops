# Architecture

CoinOps is a Kubernetes-deployed Polymarket intelligence dashboard.

## Public Request Path

```text
Browser
  |
  v
Cloudflare DNS
  |
  v
GCP L4 Load Balancer
  |
  v
k3s nodes
  |
  v
Traefik Ingress Controller
  |
  v
Kubernetes Ingress
  |
  +-- /             -> coinops-ui
  +-- /api          -> coinops-proxy
  +-- /history-api  -> coinops-history-api
```

The browser stays same-origin and calls only:

- `/api`
- `/history-api`

It must not call internal Kubernetes service DNS names directly.

## Namespaces

| Namespace | Components |
| --- | --- |
| `cnpg-system` | CloudNativePG operator |
| `coinops-data` | PostgreSQL, RabbitMQ, Redis, data-layer secrets |
| `coinops-backend` | Go proxy, history API, history consumer |
| `coinops-frontend` | React UI, frontend Ingress, TLS Secret |

## Components

### UI

Path: `ui-react/`

The React/Vite frontend is built into an nginx container. In Kubernetes it runs
as the `coinops-ui` Deployment and receives runtime paths:

- `PROXY_URL=/api`
- `HISTORY_URL=/history-api`

### Proxy

Path: `proxy/`

The Go proxy fetches live market data from public upstream APIs, manages
short-lived UI session state through Redis, and publishes normalized market and
price events to RabbitMQ.

### History Consumer

Path: `history/consumer.py`

The consumer reads RabbitMQ messages from `market_events` and writes historical
snapshots into PostgreSQL.

### History API

Path: `history/main.py`

The FastAPI service exposes read-only historical data from PostgreSQL.

Endpoints:

- `GET /health`
- `GET /history`
- `GET /history/{slug}`
- `GET /prices/history/{coin}`

### PostgreSQL

PostgreSQL is managed by CloudNativePG. The application connects to the CNPG
read/write service:

```text
coinops-postgres-rw.coinops-data.svc
```

### RabbitMQ And Redis

RabbitMQ and Redis are installed with Helm into `coinops-data`.

- RabbitMQ is the async queue between proxy and consumer.
- Redis stores short-lived UI session state.

## Deployment Automation

Application deployment entry point:

```text
ansible/coinops-app.yml
```

Role responsibilities:

| Role | Purpose |
| --- | --- |
| `cnpg_operator` | Installs CNPG with Helm |
| `coinops_data` | Creates namespaces, secrets, PostgreSQL, RabbitMQ, Redis |
| `coinops_proxy` | Deploys the Go proxy |
| `coinops_history` | Deploys history API and consumer |
| `coinops_ui` | Deploys the React UI |
| `coinops_ingress` | Creates public Ingress and TLS routing |

## Runtime Assets

The `runtime/` directory contains PostgreSQL runtime queue/session assets for
future consolidation work. The current deployed application still uses
RabbitMQ and Redis.

## Related Docs

- [k3s Cluster Runbook](k3s-cluster.md)
- [CoinOps on k3s Runbook](coinops-k3s-deployment.md)
