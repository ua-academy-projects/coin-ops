# Kubernetes (k3s) deployment

Placeholder for Helm charts / Kubernetes manifests that will deploy the
Coin-Ops application onto the k3s lab cluster.

Cluster provisioning lives in `ansible/playbooks/k3s-cluster.yml` (uses
`ansible/inventories/gcp-k3s`). See `docs/k3s-cluster.md` for the cluster
runbook.

Application migration into Kubernetes has not started yet. The current
deployment shape on `dev` is still the three-VM Docker Compose flow under
`deployments/gcp-vm/`.

Planned next steps:

- decide which services become Deployments / StatefulSets
- decide how PostgreSQL, RabbitMQ, Redis are handled (in-cluster vs Cloud SQL)
- move secrets from GCP Secret Manager into Kubernetes Secrets / external-secrets
- choose ingress (default k3s Traefik vs custom)
- wire CI to push images and apply manifests
