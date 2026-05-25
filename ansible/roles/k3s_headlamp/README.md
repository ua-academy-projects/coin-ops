# k3s_headlamp
Install [Headlamp](https://headlamp.dev) — a Kubernetes SIG web dashboard —
into the k3s learning cluster from its **official Helm chart**
(`headlamp/headlamp`, repo `https://kubernetes-sigs.github.io/headlamp/`), and
expose it through Traefik with a cert-manager TLS cert. Runs once on the first
node; joiner hosts exit (`meta: end_host`).

**Where it runs:** the first node in the `k3s` inventory group only. Applied by
the `k3s-up.yml` playbook after [[k3s]] is up, [[k3s_tools]] has installed
Helm + the Python kubernetes client, and [[k3s_cert_manager]] has the
ClusterIssuer ready.

**Reads** (all in `defaults/main.yml`):
- `k3s_headlamp_chart_version` — pinned chart version (`0.42.0`).
- `k3s_headlamp_image_tag` — optional image-tag pin (empty == chart default).
- `k3s_ingress_domain`, `cert_manager_cluster_issuer` — shared ingress/TLS
  inputs; `k3s_headlamp_host` is `headlamp.<domain>`.

**Produces:** in the `tooling` namespace — the chart's ServiceAccount + a
`cluster-admin` ClusterRoleBinding, the Headlamp Deployment + Service, and a
Traefik `Ingress` for `headlamp.<domain>` with the `headlamp-tls` cert
auto-issued by cert-manager. Values are rendered from
`templates/headlamp-values.yaml.j2`.

**Reaching it:** browse to `https://headlamp.<domain>` from a tailnet client
(the wildcard `*.<domain>` resolves to a k3s node private IP, routed through
the GCP bastion). Log in with a token minted from the chart's ServiceAccount
(named after the release, `headlamp`):

```bash
kubectl --kubeconfig=~/.kube/coinops-k3s.yaml \
  -n tooling create token headlamp --duration=24h
```

**Security note:** the dashboard SA is `cluster-admin` for learning
convenience — a token minted from it has full read/write. Scope
`clusterRoleBinding.clusterRoleName` (in the rendered values) down to a
read-only ClusterRole before putting any real workload on the cluster. The
ingress is only reachable through the bastion/tailnet, never the public
internet.

Pin `k3s_headlamp_image_tag` for reproducible rollouts; the default tracks the
chart's bundled appVersion.
