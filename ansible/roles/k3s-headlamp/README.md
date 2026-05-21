# k3s-headlamp

Deploy [Headlamp](https://headlamp.dev) — a Kubernetes SIG web dashboard —
into the k3s learning cluster, on first run, then exit on all joiner hosts.

**Where it runs:** the first node in the `k3s` inventory group only
(`meta: end_host` exits joiners). Applied by the [[k3s-cluster]] meta-role
after [[k3s]] has the cluster up.

**Reads:** `k3s_first_node` from [[k3s]]; `k3s_headlamp_image` and
`k3s_headlamp_nodeport` from this role's `defaults/main.yml`.

**Produces:** the `headlamp` namespace, a `headlamp-admin` ServiceAccount
bound to `cluster-admin`, the Headlamp Deployment, and a NodePort Service
on `:30081`.

**Reaching it:** from a tailnet client with `--accept-routes`, browse to
`http://10.10.20.40:30081` (any k3s node's private IP, routed through the
GCP bastion). Log in with a token:

```bash
kubectl --kubeconfig=~/.kube/coinops-k3s.yaml \
  -n headlamp create token headlamp-admin --duration=24h
```

**Security note:** the dashboard SA is `cluster-admin` for learning
convenience — a token minted from it has full read/write. Tighten to a
scoped ClusterRole before putting any real workload on the cluster. The
`:30081` NodePort is only reachable through the bastion (firewall rule
`k3s_from_bastion`), never from the public internet.

Pin `k3s_headlamp_image` to a tagged release for reproducible rollouts;
the default tracks `:latest`.
