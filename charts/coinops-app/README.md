# coinops-app Helm chart

Packages the Coin-Ops application workloads — proxy, history-api, history-consumer, ui, gateway — plus 18 app-tier NetworkPolicies that enforce the per-workload namespace boundary.

## What it deploys

- 4 Namespaces (proxy / history-api / history-consumer / ui; gateway is the release namespace, created by `--create-namespace`)
- 5 ServiceAccounts, 5 Deployments, 4 Services
- 3 cross-namespace ConfigMaps (`coinops-app-config`) and 3 Secrets (`coinops-app-secrets`)
- 4 image-pull Secrets (`ghcr-pull`) for private GHCR images
- 1 nginx ConfigMap + Ingress for the gateway
- 18 NetworkPolicies: 5 default-deny + 5 allow-dns + 8 flow policies

Data-tier NetworkPolicies (rabbitmq, redis, postgres) are owned by the `k3s_netpol` Ansible role.

## Prerequisites

- k3s with kube-router NetworkPolicy controller
- CNPG operator + a running `coinops-pg` Cluster in `coinops-postgres`
- RabbitMQ StatefulSet in `coinops-rabbitmq`; Redis StatefulSet in `coinops-redis`
- cert-manager `ClusterIssuer` matching `ingress.certManagerClusterIssuer`
- Traefik ingress controller

## Install

The connection URLs and image pull secret are required. A minimum `my-values.yaml`:

```yaml
image:
  tag: dev-latest
  pullSecretDockerconfigjson: <base64 of {"auths":{"ghcr.io":{"auth":"..."}}}>
ingress:
  host: app.coinops.pp.ua
app:
  databaseUrl: postgresql://user:pass@coinops-pg-rw.coinops-postgres.svc.cluster.local:5432/cognitor
  rabbitmqUrl: amqp://user:pass@rabbitmq.coinops-rabbitmq.svc.cluster.local:5672/
  redisUrl: redis://redis.coinops-redis.svc.cluster.local:6379/0
```

Then:

```bash
helm upgrade --install coinops-app ./charts/coinops-app \
  -n coinops-gateway --create-namespace \
  --values my-values.yaml
```

Forgetting any of the `app.*` URLs makes `helm install` fail immediately with `app.<key> must be set` — no half-deployed state.

## Roll back

```bash
helm history coinops-app -n coinops-gateway
helm rollback coinops-app <revision> -n coinops-gateway
```
