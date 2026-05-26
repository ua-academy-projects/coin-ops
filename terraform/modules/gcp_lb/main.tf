# gcp_lb/main.tf
# Regional TCP Load Balancer for k3s cluster.
# Distributes ports 80 and 443 across all 3 k3s nodes.
# Traefik (running on each node) handles TLS termination and routing.
#
# Architecture:
#   Internet → GCP TCP LB (static IP) → k3s nodes (all 3) → Traefik → Services

locals {
  # Only create LB resources when deploying to GCP
  create = contains(["gcp", "hybrid"], var.config.general.cloud) ? 1 : 0
}

# Static external IP for the Load Balancer.
# Unlike VM IPs, this persists across terraform apply/destroy cycles.
# DNS record in Cloudflare should point to this IP.
resource "google_compute_address" "lb_ip" {
  count  = local.create
  name   = "coinops-lb-ip"
  region = var.config.locations[var.config.general.location].gcp.region
}

# Firewall: allow HTTP/HTTPS from internet to k3s nodes.
# k3s-server tag matches all 3 nodes.
resource "google_compute_firewall" "allow_http_https" {
  count   = local.create
  name    = "allow-http-https-k3s"
  network = var.network

  allow {
    protocol = "tcp"
    # 80 = HTTP (also used by cert-manager ACME HTTP challenge)
    # 443 = HTTPS (Traefik TLS termination)
    ports = ["80", "443"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["k3s-server"]
}

# Firewall: allow GCP health checker IP ranges to reach k3s nodes.
# GCP health checks come from these specific IP ranges — must be allowed.
resource "google_compute_firewall" "allow_health_check" {
  count   = local.create
  name    = "allow-lb-health-check-k3s"
  network = var.network

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }

  # Official GCP health checker source ranges — do not change
  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]
  target_tags   = ["k3s-server"]
}

# Instance groups — one per zone (GCP requires zone-specific groups).
# Each group contains the k3s node(s) in that zone.
# for_each creates one group per unique zone.
resource "google_compute_instance_group" "k3s" {
  for_each = local.create == 1 ? var.k3s_instance_zones : {}

  name = "coinops-k3s-${replace(each.key, ".", "-")}"
  zone = each.value

  # Each instance group contains the node for this zone
  instances = [
    "zones/${each.value}/instances/${each.key}"
  ]

  # Named port maps "http" → 80 so backend service can reference by name
  named_port {
    name = "http"
    port = 80
  }

  named_port {
    name = "https"
    port = 443
  }
}

# Health check — verifies k3s nodes are alive before sending traffic.
# Checks /health endpoint on port 80 (Traefik responds to this).
resource "google_compute_health_check" "k3s" {
  count = local.create
  name  = "coinops-k3s-health"

  http_health_check {
    port         = 80
    request_path = "/health"
  }
}

# Backend service — defines the pool of k3s nodes to send traffic to.
# EXTERNAL = accepts traffic from internet.
resource "google_compute_backend_service" "k3s" {
  count                 = local.create
  name                  = "coinops-k3s-backend"
  protocol              = "HTTP"
  load_balancing_scheme = "EXTERNAL"
  health_checks         = [google_compute_health_check.k3s[0].id]

  # Add all instance groups (one per zone) as backends
  dynamic "backend" {
    for_each = google_compute_instance_group.k3s
    content {
      group = backend.value.id
    }
  }
}

# URL map — routes all traffic to k3s backend service.
resource "google_compute_url_map" "k3s" {
  count           = local.create
  name            = "coinops-k3s-url-map"
  default_service = google_compute_backend_service.k3s[0].id
}

# HTTP proxy — handles port 80 traffic.
resource "google_compute_target_http_proxy" "k3s" {
  count   = local.create
  name    = "coinops-k3s-http-proxy"
  url_map = google_compute_url_map.k3s[0].id
}

# Forwarding rule port 80 — directs HTTP traffic to HTTP proxy.
resource "google_compute_global_forwarding_rule" "http" {
  count                 = local.create
  name                  = "coinops-k3s-http"
  target                = google_compute_target_http_proxy.k3s[0].id
  ip_address            = google_compute_address.lb_ip[0].id
  port_range            = "80"
  load_balancing_scheme = "EXTERNAL"
}

# SSL proxy — handles port 443 traffic.
# UNMANAGED = Traefik manages certificates, not GCP.
resource "google_compute_ssl_policy" "k3s" {
  count           = local.create
  name            = "coinops-k3s-ssl-policy"
  profile         = "MODERN"
  min_tls_version = "TLS_1_2"
}

# TCP proxy for HTTPS — passes 443 traffic through to Traefik unchanged.
resource "google_compute_target_tcp_proxy" "k3s_https" {
  count           = local.create
  name            = "coinops-k3s-https-proxy"
  backend_service = google_compute_backend_service.k3s[0].id
}

# Forwarding rule port 443 — directs HTTPS traffic to TCP proxy.
resource "google_compute_global_forwarding_rule" "https" {
  count                 = local.create
  name                  = "coinops-k3s-https"
  target                = google_compute_target_tcp_proxy.k3s_https[0].id
  ip_address            = google_compute_address.lb_ip[0].id
  port_range            = "443"
  load_balancing_scheme = "EXTERNAL"
}