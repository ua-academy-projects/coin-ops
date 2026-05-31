# k3s_argocd

Install ArgoCD (argo/argo-cd Helm chart) on the first k3s node, seed a read-only
GitHub repo credential (reuses `coinops_ghcr_token`/`coinops_ghcr_username` — the
token must have repo/contents read scope), expose the UI at
`https://argocd.<domain>` through Traefik + cert-manager (gated by Cloudflare
Access at the edge), and apply the `gitops/root.yaml` app-of-apps.

ArgoCD then owns the stateless workloads (`coinops-app`, `homepage`, `headlamp`,
`hello`). The stateful/operator platform stays Ansible-managed. Secrets are
seeded by `k3s_coinops`, never committed to git; ArgoCD ignores them.

Runs once on the first node (`meta: end_host` on joiners). Requires `k3s_tools`
(Helm + kubernetes python client) and `k3s_cert_manager` (for the UI cert) to
have run first.

Mint the admin password:

    k3s kubectl -n argocd get secret argocd-initial-admin-secret \
      -o jsonpath='{.data.password}' | base64 -d
