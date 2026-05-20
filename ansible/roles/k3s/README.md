# k3s

Bring up an HA k3s cluster where every node is both control-plane AND
worker (embedded etcd, no server/agent split). The first host in the
`k3s` inventory group runs `k3s server --cluster-init`; the rest join
with `--server https://first:6443` sharing the cluster token persisted
at `/var/lib/rancher/k3s/server/coinops-token` on the first node.

**Where it runs:** every host in the `k3s` inventory group, via the
[[k3s-cluster]] meta-role.

**Reads:**
- `k3s_release_version` — pinned k3s release (see `defaults/main.yml`).
- `k3s_first_node` — defaults to `ansible_play_hosts_all[0]`.
- `coinops_tailnet_ipv4` — produced by the [[tailscale]] role; used as a
  TLS SAN on the first node's API server and as the rewritten server URL
  in the fetched kubeconfig so `kubectl` works from anywhere in the
  tailnet.

**Produces:**
- Running k3s server process on every node.
- `~/.kube/coinops-k3s.yaml` on the Ansible controller, with the server
  URL rewritten to the first node's tailnet IP.
- `kubectl --kubeconfig=~/.kube/coinops-k3s.yaml get nodes` shows 3
  nodes Ready, each with role `control-plane,etcd,master`.

**Idempotency:** the role detects existing k3s installs via `k3s --version`
and skips the installer when the pinned release is already present.

See `docs/k3s-learning-track.md` at the repo root for the operator-facing
story: why GCP, why all-server, what to learn from it.
