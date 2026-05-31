# coinops-app Helm chart

Packages the Coin-Ops application workloads — proxy, history-api, history-consumer, ui, gateway — plus 18 app-tier NetworkPolicies that enforce the per-workload namespace boundary.

## What it deploys

- 4 Namespaces (proxy / history-api / history-consumer / ui), labelled `coinops-tier: app`; gateway is the release namespace, created by `--create-namespace`
- 5 ServiceAccounts, 5 Deployments, 4 Services
- 3 cross-namespace ConfigMaps (`coinops-app-config`)
- 1 nginx ConfigMap + Ingress for the gateway
- 18 NetworkPolicies: 5 default-deny + 5 allow-dns + 8 flow policies

The chart does NOT create any Secret.

Data-tier NetworkPolicies (rabbitmq, redis, postgres) are owned by the `k3s_netpol` Ansible role.

## Secrets (provided externally)

The workloads reference two Secrets BY NAME, but the chart never creates them:

- `coinops-app-secrets` — supplies `DATABASE_URL`, `RABBITMQ_URL`, `REDIS_URL` via `envFrom.secretRef`
- `ghcr-pull` — GHCR auth, referenced via `imagePullSecrets`

Their values are seeded by the Ansible `k3s_coinops` role from the cloud secret manager, into the app namespaces. They are intentionally absent from this chart and from git. ArgoCD ignores them during reconciliation.

## Prerequisites

- k3s with kube-router NetworkPolicy controller
- CNPG operator + a running `coinops-pg` Cluster in `coinops-postgres`
- RabbitMQ StatefulSet in `coinops-rabbitmq`; Redis StatefulSet in `coinops-redis`
- cert-manager `ClusterIssuer` matching `ingress.certManagerClusterIssuer`
- Traefik ingress controller
- The `coinops-app-secrets` and `ghcr-pull` Secrets pre-seeded in the app namespaces (Ansible `k3s_coinops` role)

## Install / management

The chart is reconciled by ArgoCD via `gitops/apps/coinops-app.yaml`. The non-secret values live in that Application's `helm.valuesObject` — there is no manual `helm install` in the normal flow.

To render and inspect the manifests locally:

```bash
helm template charts/coinops-app
```

## Roll back

Under GitOps, rollback is a `git revert` of the offending gitops change (ArgoCD re-syncs to the reverted state) or a sync to a previous revision from the ArgoCD UI history.

`helm history` / `helm rollback` apply only if the chart was installed manually outside ArgoCD.
