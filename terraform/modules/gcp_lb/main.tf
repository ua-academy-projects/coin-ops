# gcp_lb/main.tf
# Global TCP/HTTP Load Balancer for k3s cluster.
# Port 80  → HTTP proxy  → HTTP backend service  → k3s nodes → Traefik
# Port 443 → TCP proxy   → TCP backend service   → k3s nodes → Traefik (handles TLS)

locals {
  create = contains(["gcp", "hybrid"], var.config.general.cloud) ? 1 : 0
}

# Global static IP — persists across apply/destroy cycles.
# Global forwarding rules require global (not regional) IP addresses.
resource "google_compute_address" "lb_ip" {
  count        = local.create
  name         = "coinops-lb-ip"
  address_type = "EXTERNAL"
  # No region field = global address
}

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

resource "google_compute_instance_group" "k3s" {
  for_each = local.create == 1 ? var.k3s_instance_zones : {}
  name     = "coinops-k3s-${replace(each.key, ".", "-")}"
  zone     = each.value
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

resource "google_compute_health_check" "k3s" {
  count = local.create
  name  = "coinops-k3s-health"
  http_health_check {
    port         = 80
    request_path = "/health"
  }
}

# HTTP backend service — protocol HTTP, used for port 80
resource "google_compute_backend_service" "k3s_http" {
  count                 = local.create
  name                  = "coinops-k3s-backend-http"
  protocol              = "HTTP"
  load_balancing_scheme = "EXTERNAL"
  health_checks         = [google_compute_health_check.k3s[0].id]
  dynamic "backend" {
    for_each = google_compute_instance_group.k3s
    content { group = backend.value.id }
  }
}

# TCP backend service — protocol TCP, required by target_tcp_proxy for port 443
resource "google_compute_backend_service" "k3s_tcp" {
  count                 = local.create
  name                  = "coinops-k3s-backend-tcp"
  protocol              = "TCP"
  load_balancing_scheme = "EXTERNAL"
  health_checks         = [google_compute_health_check.k3s[0].id]
  dynamic "backend" {
    for_each = google_compute_instance_group.k3s
    content { group = backend.value.id }
  }
}

resource "google_compute_url_map" "k3s" {
  count           = local.create
  name            = "coinops-k3s-url-map"
  default_service = google_compute_backend_service.k3s_http[0].id
}

resource "google_compute_target_http_proxy" "k3s" {
  count   = local.create
  name    = "coinops-k3s-http-proxy"
  url_map = google_compute_url_map.k3s[0].id
}

# Port 80 forwarding rule → HTTP proxy
resource "google_compute_global_forwarding_rule" "http" {
  count                 = local.create
  name                  = "coinops-k3s-http"
  target                = google_compute_target_http_proxy.k3s[0].id
  ip_address            = google_compute_address.lb_ip[0].id
  port_range            = "80"
  load_balancing_scheme = "EXTERNAL"
}

resource "google_compute_ssl_policy" "k3s" {
  count           = local.create
  name            = "coinops-k3s-ssl-policy"
  profile         = "MODERN"
  min_tls_version = "TLS_1_2"
}

# TCP proxy uses TCP backend service — passes 443 traffic raw to Traefik
resource "google_compute_target_tcp_proxy" "k3s_https" {
  count           = local.create
  name            = "coinops-k3s-https-proxy"
  backend_service = google_compute_backend_service.k3s_tcp[0].id
}

# Port 443 forwarding rule → TCP proxy
resource "google_compute_global_forwarding_rule" "https" {
  count                 = local.create
  name                  = "coinops-k3s-https"
  target                = google_compute_target_tcp_proxy.k3s_https[0].id
  ip_address            = google_compute_address.lb_ip[0].id
  port_range            = "443"
  load_balancing_scheme = "EXTERNAL"
}