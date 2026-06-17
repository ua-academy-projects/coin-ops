# Cloudflare Zero Trust for the GKE chapter. One tunnel whose connector runs IN
# GKE (gke-addons.tf cloudflared), exposing the app (public) + Jenkins UI (behind
# Access). Mirrors cloudflare_zerotrust.tf (k3s). Gated on cloudflared.enabled +
# an account_id. VALIDATE on the live cluster (cloudflare provider v5).
locals {
  gke_cf_enabled = local.gke_cloudflared_enabled && local.cf_account_id != ""
  gke_cf_hosts = {
    app     = "gke.${local.k3s_ingress_domain}"     # public — the coin-ops app
    jenkins = "jenkins.${local.k3s_ingress_domain}" # behind Cloudflare Access
  }
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "gke" {
  count      = local.gke_cf_enabled ? 1 : 0
  account_id = local.cf_account_id
  name       = "${local.config.name_prefix}-gke"
  config_src = "cloudflare"
}

data "cloudflare_zero_trust_tunnel_cloudflared_token" "gke" {
  count      = local.gke_cf_enabled ? 1 : 0
  account_id = local.cf_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.gke[0].id
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "gke" {
  count      = local.gke_cf_enabled ? 1 : 0
  account_id = local.cf_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.gke[0].id

  config = {
    ingress = [
      { hostname = local.gke_cf_hosts.app, service = "http://gateway.coinops-gateway.svc.cluster.local:80" },
      { hostname = local.gke_cf_hosts.jenkins, service = "http://jenkins.jenkins.svc.cluster.local:8080" },
      { service = "http_status:404" },
    ]
  }
}

resource "cloudflare_dns_record" "gke" {
  for_each = local.gke_cf_enabled ? local.gke_cf_hosts : {}

  zone_id = local.config.domain.cloudflare_zone_id
  name    = each.value
  type    = "CNAME"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.gke[0].id}.cfargotunnel.com"
  ttl     = 1
  proxied = true
}

# Jenkins UI gated to the operator emails (built-in one-time PIN).
resource "cloudflare_zero_trust_access_policy" "gke_operators" {
  count      = local.gke_cf_enabled ? 1 : 0
  account_id = local.cf_account_id
  name       = "${local.config.name_prefix}-gke-operators"
  decision   = "allow"
  include    = [for email in local.cf_access_emails : { email = { email = email } }]
}

resource "cloudflare_zero_trust_access_application" "gke_jenkins" {
  count      = local.gke_cf_enabled ? 1 : 0
  account_id = local.cf_account_id
  name       = "coinops-gke-jenkins"
  domain     = local.gke_cf_hosts.jenkins
  type       = "self_hosted"

  policies = [{
    id         = cloudflare_zero_trust_access_policy.gke_operators[0].id
    precedence = 1
  }]
}

# Tunnel token -> Secret Manager (parity with the k3s tunnels).
resource "google_secret_manager_secret" "gke_cf_tunnel" {
  count     = local.gke_cf_enabled ? 1 : 0
  secret_id = "${local.config.name_prefix}-cloudflare-tunnel-token-gke"
  replication {
    auto {}
  }
  labels = { app = local.config.name_prefix }
}

resource "google_secret_manager_secret_version" "gke_cf_tunnel" {
  count       = local.gke_cf_enabled ? 1 : 0
  secret      = google_secret_manager_secret.gke_cf_tunnel[0].id
  secret_data = data.cloudflare_zero_trust_tunnel_cloudflared_token.gke[0].token
}
