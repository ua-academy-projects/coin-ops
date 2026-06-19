# Homepage on k3s

Homepage is an optional platform workload installed into the existing k3s ingress path.

This is a legacy self-managed k3s runbook. The active EKS playbooks do not
deploy Homepage, even though shared config/DNS fields remain. Homepage is not a
current AWS acceptance requirement.

## Deploy

```bash
cd /home/notebook/projects/coin-ops
source local/generated-env.sh
make k3s-cluster
make k3s-homepage
```

The role stages its local Helm chart, renders values, installs or upgrades the release, and configures ingress/TLS through shared k3s roles.

## Validate

```bash
make k8s-api-ready
make kubectl ARGS='get pods -n homepage'
make kubectl ARGS='get ingress -n homepage'
```

Homepage uses a dedicated service account and read-only RBAC for the Kubernetes widget.
