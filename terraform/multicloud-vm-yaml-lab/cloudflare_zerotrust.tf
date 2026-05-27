# Cloudflare Zero Trust — the GCP k3s edge, replacing Tailscale.
#
# Two cloudflared tunnels (a single tunnel load-balances across all its
# connectors, so in-cluster and bastion routing cannot share one):
#   - apps  : connectors run IN the cluster (k3s_cloudflared role) and forward
#             every app hostname to in-cluster Traefik, which host-routes via
#             the Ingresses. app.* is public; the rest sit behind Access.
#   - admin : the connector runs on the bastion (cloud_bastion_stack) and
#             exposes SSH (ansible ProxyJump) + the k3s API (kubectl) behind
#             Access — no public ports, no Tailscale.
#
# Terraform creates the tunnels, reads their tokens, defines the routing,
# the proxied DNS, the Access policy/apps, and writes the tokens into GCP
# Secret Manager so the existing cloud_secrets flow feeds cloudflared.
#
# Entirely inert unless: backend cloud is GCP, k3s nodes exist, an account_id
# is set, and domain.zero_trust.enabled is true. So it is a no-op on the AWS
# compose path (cloud: aws).

variable "github_oauth_client_id" {
  type        = string
  default     = ""
  description = "GitHub OAuth App Client ID for Cloudflare Access GitHub login. Set via TF_VAR_github_oauth_client_id."
}

variable "github_oauth_client_secret" {
  type        = string
  default     = ""
  sensitive   = true
  description = "GitHub OAuth App Client Secret. Set via TF_VAR_github_oauth_client_secret."
}

locals {
  cf_account_id      = try(local.config.domain.cloudflare_account_id, "")
  cf_access_emails   = try(local.config.domain.zero_trust.access_emails, [])
  zero_trust_enabled = local.is_gcp && length(local.k3s_names) > 0 && try(local.config.domain.zero_trust.enabled, false) && local.cf_account_id != ""
  cf_github_enabled  = local.zero_trust_enabled && var.github_oauth_client_id != ""

  # Hostnames served through the tunnels (<name>.<k3s_ingress_domain>).
  cf_apps_hostnames = {
    app      = "app.${local.k3s_ingress_domain}"
    headlamp = "headlamp.${local.k3s_ingress_domain}"
    homepage = "homepage.${local.k3s_ingress_domain}"
    hello    = "hello.${local.k3s_ingress_domain}"
  }
  cf_admin_hostnames = {
    ssh = "ssh.${local.k3s_ingress_domain}"
    k8s = "k8s.${local.k3s_ingress_domain}"
  }

  # Access-gated set: every tunnel hostname except the public app. Empty (so no
  # Access apps) until zero_trust is enabled.
  cf_access_hostnames = local.zero_trust_enabled ? merge(
    { for k, v in local.cf_apps_hostnames : k => v if k != "app" },
    local.cf_admin_hostnames,
  ) : {}

  # The admin tunnel's kube-API target: the first k3s node, reachable from the
  # bastion over the VPC.
  cf_k3s_api_ip = local.zero_trust_enabled ? local.instances[local.k3s_names[0]].private_ip : ""
}

# --- Tunnels -----------------------------------------------------------------

resource "cloudflare_zero_trust_tunnel_cloudflared" "apps" {
  count      = local.zero_trust_enabled ? 1 : 0
  account_id = local.cf_account_id
  name       = "${local.config.name_prefix}-k3s-apps"
  config_src = "cloudflare"
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "admin" {
  count      = local.zero_trust_enabled ? 1 : 0
  account_id = local.cf_account_id
  name       = "${local.config.name_prefix}-k3s-admin"
  config_src = "cloudflare"
}

data "cloudflare_zero_trust_tunnel_cloudflared_token" "apps" {
  count      = local.zero_trust_enabled ? 1 : 0
  account_id = local.cf_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.apps[0].id
}

data "cloudflare_zero_trust_tunnel_cloudflared_token" "admin" {
  count      = local.zero_trust_enabled ? 1 : 0
  account_id = local.cf_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.admin[0].id
}

# --- GitHub identity provider (login method) ---------------------------------
# Requires a GitHub OAuth App (github.com > Settings > Developer settings >
# OAuth Apps). Authorization callback URL:
#   https://<team-name>.cloudflareaccess.com/cdn-cgi/access/callback
# client_id/secret arrive via TF_VAR_github_oauth_client_id / _secret.
resource "cloudflare_zero_trust_access_identity_provider" "github" {
  count      = local.cf_github_enabled ? 1 : 0
  account_id = local.cf_account_id
  name       = "GitHub"
  type       = "github"
  config = {
    client_id     = var.github_oauth_client_id
    client_secret = var.github_oauth_client_secret
  }
}

# --- Routing -----------------------------------------------------------------

# Apps: every hostname -> in-cluster Traefik (the connector resolves cluster
# DNS). Traefik then host-routes to the app/dashboard Services via the Ingresses.
resource "cloudflare_zero_trust_tunnel_cloudflared_config" "apps" {
  count      = local.zero_trust_enabled ? 1 : 0
  account_id = local.cf_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.apps[0].id

  config = {
    ingress = concat(
      [for key, host in local.cf_apps_hostnames : {
        hostname = host
        service  = "http://traefik.kube-system.svc.cluster.local:80"
      }],
      [{ service = "http_status:404" }],
    )
  }
}

# Admin: SSH to the bastion itself + TCP to the k3s API. Connector runs on the
# bastion, which reaches its own sshd (localhost:22) and the node over the VPC.
resource "cloudflare_zero_trust_tunnel_cloudflared_config" "admin" {
  count      = local.zero_trust_enabled ? 1 : 0
  account_id = local.cf_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.admin[0].id

  config = {
    ingress = [
      { hostname = local.cf_admin_hostnames.ssh, service = "ssh://localhost:22" },
      { hostname = local.cf_admin_hostnames.k8s, service = "tcp://${local.cf_k3s_api_ip}:6443" },
      { service = "http_status:404" },
    ]
  }
}

# --- DNS (proxied CNAMEs to the tunnels) -------------------------------------

resource "cloudflare_dns_record" "cf_apps" {
  for_each = local.zero_trust_enabled ? local.cf_apps_hostnames : {}

  zone_id = local.config.domain.cloudflare_zone_id
  name    = each.value
  type    = "CNAME"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.apps[0].id}.cfargotunnel.com"
  ttl     = 1
  proxied = true
}

resource "cloudflare_dns_record" "cf_admin" {
  for_each = local.zero_trust_enabled ? local.cf_admin_hostnames : {}

  zone_id = local.config.domain.cloudflare_zone_id
  name    = each.value
  type    = "CNAME"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.admin[0].id}.cfargotunnel.com"
  ttl     = 1
  proxied = true
}

# --- Access (login = the listed emails, built-in one-time PIN) ---------------

resource "cloudflare_zero_trust_access_policy" "operators" {
  count      = local.zero_trust_enabled ? 1 : 0
  account_id = local.cf_account_id
  name       = "${local.config.name_prefix}-operators"
  decision   = "allow"
  include    = [for email in local.cf_access_emails : { email = { email = email } }]
}

resource "cloudflare_zero_trust_access_application" "gated" {
  for_each = local.cf_access_hostnames

  account_id = local.cf_account_id
  name       = "coinops-${each.key}"
  domain     = each.value
  type       = "self_hosted"

  allowed_idps              = local.cf_github_enabled ? [cloudflare_zero_trust_access_identity_provider.github[0].id] : null
  auto_redirect_to_identity = local.cf_github_enabled

  policies = [{
    id         = cloudflare_zero_trust_access_policy.operators[0].id
    precedence = 1
  }]
}

# --- Tunnel tokens -> GCP Secret Manager -------------------------------------
# Terraform holds the tokens (from the data sources) and writes them as secret
# versions, so cloud_secrets fetches them like every other secret — no manual
# token handling. Deterministic names: <name_prefix>-cloudflare-tunnel-token-*.

resource "google_secret_manager_secret" "cf_tunnel_apps" {
  count     = local.zero_trust_enabled ? 1 : 0
  secret_id = "${local.config.name_prefix}-cloudflare-tunnel-token-apps"
  replication {
    auto {}
  }
  labels = { app = local.config.name_prefix }
}

resource "google_secret_manager_secret_version" "cf_tunnel_apps" {
  count       = local.zero_trust_enabled ? 1 : 0
  secret      = google_secret_manager_secret.cf_tunnel_apps[0].id
  secret_data = data.cloudflare_zero_trust_tunnel_cloudflared_token.apps[0].token
}

resource "google_secret_manager_secret" "cf_tunnel_admin" {
  count     = local.zero_trust_enabled ? 1 : 0
  secret_id = "${local.config.name_prefix}-cloudflare-tunnel-token-admin"
  replication {
    auto {}
  }
  labels = { app = local.config.name_prefix }
}

resource "google_secret_manager_secret_version" "cf_tunnel_admin" {
  count       = local.zero_trust_enabled ? 1 : 0
  secret      = google_secret_manager_secret.cf_tunnel_admin[0].id
  secret_data = data.cloudflare_zero_trust_tunnel_cloudflared_token.admin[0].token
}
