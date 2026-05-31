# gitops/

ArgoCD's source of truth for the **stateless** workloads on the GCP k3s cluster.

## The boundary

> Ansible lays down the cluster and the stateful platform (k3s, CNPG + Postgres,
> cert-manager, rabbitmq, redis, data-tier NetworkPolicies, cloudflared) and
> bootstraps ArgoCD + Kyverno. Git describes every stateless workload. ArgoCD
> reconciles them. Kyverno enforces the rules.

## Tree

- `root.yaml` — app-of-apps; the only Application Ansible applies. Watches `apps/`.
- `apps/coinops-app.yaml` — the app, from the local Helm chart `charts/coinops-app`.
- `apps/homepage.yaml` — gethomepage.dev, upstream Helm chart + frozen values.
- `apps/headlamp.yaml` — Headlamp dashboard, upstream Helm chart + frozen values.
- `apps/hello.yaml` — nginxdemos/hello, raw manifests under `manifests/hello/`.
- `manifests/hello/` — raw manifests for the hello workload.

## Secrets are never in git

`coinops-app` references two Secrets by name — `coinops-app-secrets` (DB/queue/cache
URLs) and `ghcr-pull` (registry auth). Their **values** are seeded by the Ansible
`k3s_coinops` role from the cloud secret manager. ArgoCD is told to ignore those
Secrets (`ignoreDifferences` in `apps/coinops-app.yaml`). Where this goes next:
Sealed Secrets or the External Secrets Operator.
