# gcp_lb/main.tf
# Regional Network Load Balancer (pass-through) for k3s cluster.
# Pass-through = LB forwards TCP packets unchanged to Traefik.
# Traefik receives original TLS connection, terminates it, routes by domain.
# cert-manager manages TLS certificates via Let's Encrypt.
#
# Architecture:
#   Internet → Regional NLB (pass-through) → k3s nodes → Traefik → Services

locals {
  create = contains(["gcp", "hybrid"], var.config.general.cloud) ? 1 : 0
  region = var.config.locations[var.config.general.location].gcp.region
}

# Static regional IP — used by regional forwarding rules
resource "google_compute_address" "lb_ip" {
  count  = local.create
  name   = "coinops-lb-ip"
  region = local.region
}

# Allow HTTP/HTTPS from internet to k3s nodes
resource "google_compute_firewall" "allow_http_https" {
  count   = local.create
  name    = "allow-http-https-k3s"
  network = var.network
  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["k3s-server"]
}

# Allow GCP health checker IP ranges
resource "google_compute_firewall" "allow_health_check" {
  count   = local.create
  name    = "allow-lb-health-check-k3s"
  network = var.network
  allow {
    protocol = "tcp"
    ports    = ["80"]
  }
  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]
  target_tags   = ["k3s-server"]
}

# Data source — looks up existing VM self_link by name+zone
data "google_compute_instance" "k3s" {
  for_each = local.create == 1 ? var.k3s_instance_zones : {}
  name     = each.key
  zone     = each.value
}

# Instance groups — one per zone
resource "google_compute_instance_group" "k3s" {
  for_each  = local.create == 1 ? var.k3s_instance_zones : {}
  name      = "coinops-k3s-${replace(each.key, ".", "-")}"
  zone      = each.value
  instances = [data.google_compute_instance.k3s[each.key].self_link]
  named_port {
    name = "http"
    port = 80
  }
  named_port {
    name = "https"
    port = 443
  }
}

# TCP health check — verifies Traefik accepts connections on port 80
resource "google_compute_health_check" "k3s" {
  count = local.create
  name  = "coinops-k3s-health"
  tcp_health_check {
    port = 80
  }
}

# Regional backend service — HTTP for port 80
resource "google_compute_region_backend_service" "k3s_http" {
  count                 = local.create
  name                  = "coinops-k3s-backend-http"
  region                = local.region
  protocol              = "TCP"
  load_balancing_scheme = "EXTERNAL"
  health_checks         = [google_compute_health_check.k3s[0].id]

  dynamic "backend" {
    for_each = google_compute_instance_group.k3s
    content {
      group = backend.value.id
    }
  }
}

# Regional backend service — TCP for port 443 (pass-through)
resource "google_compute_region_backend_service" "k3s_https" {
  count                 = local.create
  name                  = "coinops-k3s-backend-https"
  region                = local.region
  protocol              = "TCP"
  load_balancing_scheme = "EXTERNAL"
  health_checks         = [google_compute_health_check.k3s[0].id]

  dynamic "backend" {
    for_each = google_compute_instance_group.k3s
    content {
      group = backend.value.id
    }
  }
}

# Forwarding rule port 80
resource "google_compute_forwarding_rule" "http" {
  count                 = local.create
  name                  = "coinops-k3s-http"
  region                = local.region
  ip_address            = google_compute_address.lb_ip[0].address
  ip_protocol           = "TCP"
  port_range            = "80"
  load_balancing_scheme = "EXTERNAL"
  backend_service       = google_compute_region_backend_service.k3s_http[0].id
}

# Forwarding rule port 443 — pass-through to Traefik
resource "google_compute_forwarding_rule" "https" {
  count                 = local.create
  name                  = "coinops-k3s-https"
  region                = local.region
  ip_address            = google_compute_address.lb_ip[0].address
  ip_protocol           = "TCP"
  port_range            = "443"
  load_balancing_scheme = "EXTERNAL"
  backend_service       = google_compute_region_backend_service.k3s_https[0].id
}