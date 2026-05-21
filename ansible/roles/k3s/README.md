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

**Produces:**
- Running k3s server process on every node.
- `~/.kube/coinops-k3s.yaml` on the Ansible controller, with the server
  URL rewritten to the first node's **private IP** (`10.10.20.x`). That
  IP is reachable from any tailnet client because the GCP bastion
  advertises the k3s private subnet — k3s nodes themselves run no
  Tailscale.
- `kubectl --kubeconfig=~/.kube/coinops-k3s.yaml get nodes` shows 3
  nodes Ready, each with role `control-plane,etcd,master`.

**Idempotency:** the role detects existing k3s installs via `k3s --version`
and skips the installer when the pinned release is already present.

See `docs/k3s-learning-track.md` at the repo root for the operator-facing
story: why GCP, why all-server, what to learn from it.
