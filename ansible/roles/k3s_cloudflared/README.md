# k3s_cloudflared

Run [cloudflared](https://github.com/cloudflare/cloudflared) **in-cluster** as
the connector for the Coin-Ops "apps" Cloudflare Tunnel — the public/edge entry
point that replaces tailnet ingress (no node ports, no Tailscale).

**Where it runs:** the first node in the `k3s` inventory group only
(`meta: end_host` exits joiners). Applied by the `k3s-up.yml` playbook after
[[k3s_cert_manager]]. Lives in the `ingress` namespace.

**How routing works:** the tunnel is **token-based / remotely-managed** —
Terraform (`cloudflare_zerotrust.tf`) creates the tunnel, its ingress routing
(every app hostname → `traefik.kube-system.svc:80`, which host-routes via the
Ingresses), the proxied DNS, and the Access policies. Cloudflare pushes that
config to the connector, so this role carries **no ingress rules** — it just
runs `cloudflared tunnel run` with the token.

**Reads:** `k3s_cloudflared_tunnel_token` (defaults to
`coinops_cloudflare_tunnel_token_apps`, resolved by [[cloud_secrets]] from
Secret Manager), `k3s_cloudflared_replicas` (2), `k3s_cloudflared_image`,
`k3s_cloudflared_namespace` (`ingress`).

**Produces:** the `cloudflared-apps-token` Secret and a 2-replica `cloudflared`
Deployment (readiness via the `:2000/ready` metrics endpoint).

**Skips cleanly** when the token is empty (Zero Trust not enabled) — the role
no-ops with a debug message, so the cluster still comes up without Cloudflare.

`app.<domain>` is public; `headlamp` / `homepage` / `hello` are gated by
Cloudflare Access (login = the emails in `domain.zero_trust.access_emails`).
The admin path (SSH + kube API) is a separate tunnel on the bastion — see
[[cloudflared_bastion]].
