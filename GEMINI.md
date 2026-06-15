# CoinOps Context

CoinOps is a Polymarket intelligence dashboard deployed on k3s in GCP.

## Services

- `ui-react/` - React/Vite frontend served by nginx
- `proxy/` - Go HTTP proxy for live market data, sessions, and event publishing
- `history/` - FastAPI history API plus RabbitMQ consumer
- `runtime/` - PostgreSQL runtime queue/session assets for future work

## Kubernetes Deployment

The current deployment is managed by Ansible:

- `ansible/k3s-cluster.yml` bootstraps the k3s cluster
- `ansible/k3s-platform.yml` installs platform components such as cert-manager
- `ansible/coinops-app.yml` deploys CoinOps

The public application endpoint is:

```text
https://coinops.kazachuk-k3s.pp.ua/
```

Traffic path:

```text
Cloudflare DNS -> GCP L4 Load Balancer -> k3s Traefik -> Ingress -> Services -> Pods
```

## Data Services

- PostgreSQL is managed by CNPG in `coinops-data`
- RabbitMQ is installed with Helm in `coinops-data`
- Redis is installed with Helm in `coinops-data`
- app services run in `coinops-backend` and `coinops-frontend`

## Development

Run frontend checks in `ui-react/`, Go checks in `proxy/`, and Python checks
from the repository root with `python -m pytest tests/python/unit -v`.

Keep deployment work focused on the current k3s and Kubernetes path.
