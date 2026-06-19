# Headlamp on Kubernetes

The Headlamp roles are shared by EKS and legacy k3s. The active AWS path runs
Headlamp in EKS behind Cloudflare Tunnel and Access. Local port-forward remains
the fallback.

## Deploy

```bash
cd /home/notebook/projects/coin-ops
source local/generated-env.sh
make eks-headlamp
```

Terraform manages Cloudflare Tunnel, Access, DNS, and generated runtime inputs.
Ansible installs Headlamp and the shared cloudflared connector. Jenkins normally
runs the same target through `coinops-eks-deploy-headlamp` after initial
bootstrap.

## Access

Primary path:

```text
https://headlamp.coinops-d.pp.ua/
```

EKS fallback:

```bash
make eks-kubectl ARGS='-n headlamp port-forward svc/headlamp 4466:80'
```

Generate a login token:

```bash
make eks-kubectl ARGS='create token headlamp-admin -n headlamp'
```

## Notes

Cloudflare Access is an outer gate. Headlamp still requires Kubernetes
authentication. Keep generated kubeconfigs, tunnel tokens, and helper scripts
out of commits. `make headlamp-token` belongs to the legacy k3s tunneled
kubeconfig, not EKS.
