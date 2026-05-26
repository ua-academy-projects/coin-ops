# cloudflared_bastion

Install [cloudflared](https://github.com/cloudflare/cloudflared) on the GCP
bastion and run the Coin-Ops "admin" Cloudflare Tunnel as a systemd service.
This is the **operator access path** that replaces the bastion's Tailscale
subnet-router: zero-trust SSH + kube API with no public ports.

**Where it runs:** the `bastion` host, imported by [[cloud_bastion_stack]]
(alongside [[tailscale]] for now — additive until the Cloudflare path is proven,
then Tailscale is removed).

**How it works:** the tunnel is token-based / remotely-managed. Terraform
(`cloudflare_zerotrust.tf`) creates the admin tunnel and its routing —
`ssh.<domain>` → `ssh://localhost:22` (the bastion's sshd) and `k8s.<domain>` →
`tcp://<k3s-node>:6443` — behind Cloudflare Access. The connector here just runs
`cloudflared tunnel run` with the token (from an `0600` EnvironmentFile, never in
the process args).

**Reads:** `cloudflared_bastion_token` (defaults to
`coinops_cloudflare_tunnel_token_admin`, resolved by [[cloud_secrets]] from
Secret Manager).

**Produces:** the `cloudflared` package, `/etc/cloudflared/admin.env` (0600
token), and the `cloudflared-admin` systemd service (enabled + started).

**Skips cleanly** when the token is empty (Zero Trust not enabled).

**Operator usage** (no Tailscale needed):

```bash
# SSH (ansible ProxyJump): add to ~/.ssh/config or use directly
cloudflared access ssh --hostname ssh.coinops.pp.ua
# kubectl: open a local proxy to the k3s API, point kubeconfig at it
cloudflared access tcp --hostname k8s.coinops.pp.ua --url 127.0.0.1:6443
```

First use of each opens a browser for the Access one-time-PIN login.
