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
| `coinops-postgres` | CNPG PostgreSQL cluster and PostgreSQL credentials |
| `coinops-rabbitmq` | RabbitMQ and RabbitMQ credentials |
| `coinops-redis` | Redis and Redis credentials |
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
coinops-postgres-rw.coinops-postgres.svc
```

### RabbitMQ And Redis

RabbitMQ and Redis are installed with Helm into separate data namespaces:
`coinops-rabbitmq` and `coinops-redis`. This keeps the data services ready for
future NetworkPolicy isolation.

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
| `coinops_app_chart` | Installs the CoinOps application Helm chart from `charts/coinops/` (proxy, history API + consumer, UI, public Ingress, Traefik middlewares) |

The application layer is packaged as a single local Helm chart at
`charts/coinops/`. The data layer (PostgreSQL, RabbitMQ, Redis, secrets) is
intentionally outside the chart and stays under `coinops_data` because it has a
different lifecycle.

## Runtime Assets

The `runtime/` directory contains PostgreSQL runtime queue/session assets for
future consolidation work. The current deployed application still uses
RabbitMQ and Redis.

## Related Docs

- [k3s Cluster Runbook](k3s-cluster.md)
- [CoinOps on k3s Runbook](coinops-k3s-deployment.md)
