# Allow HTTP traffic to web-tagged VMs
resource "google_compute_firewall" "allow_http" {
  count   = var.config.general.cloud == "gcp" ? 1 : 0
  name    = "allow-http-web"
  network = var.network

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["web"]
}

# Allow GCP health checks to reach node-03
resource "google_compute_firewall" "allow_health_check" {
  count   = var.config.general.cloud == "gcp" ? 1 : 0
  name    = "allow-health-check"
  network = var.network

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }

  # GCP health checker IP ranges
  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]
  target_tags   = ["web"]
}

# Instance group containing node-03
resource "google_compute_instance_group" "ui" {
  count     = var.config.general.cloud == "gcp" ? 1 : 0
  name      = "coinops-ui-group"
  zone      = var.ui_instance_zone

  instances = [
    "zones/${var.ui_instance_zone}/instances/${var.ui_instance_name}"
  ]

  named_port {
    name = "http"
    port = 80
  }
}

# Health check
resource "google_compute_health_check" "ui" {
  count = var.config.general.cloud == "gcp" ? 1 : 0
  name  = "coinops-ui-health"

  http_health_check {
    port         = 80
    request_path = "/health"
  }
}

# Backend service
resource "google_compute_backend_service" "ui" {
  count                 = var.config.general.cloud == "gcp" ? 1 : 0
  name                  = "coinops-ui-backend"
  protocol              = "HTTP"
  load_balancing_scheme = "EXTERNAL"
  health_checks         = [google_compute_health_check.ui[0].id]

  backend {
    group = google_compute_instance_group.ui[0].id
  }
}

# URL map
resource "google_compute_url_map" "ui" {
  count           = var.config.general.cloud == "gcp" ? 1 : 0
  name            = "coinops-url-map"
  default_service = google_compute_backend_service.ui[0].id
}

# HTTP proxy
resource "google_compute_target_http_proxy" "ui" {
  count   = var.config.general.cloud == "gcp" ? 1 : 0
  name    = "coinops-http-proxy"
  url_map = google_compute_url_map.ui[0].id
}

# Global forwarding rule (public IP)
resource "google_compute_global_forwarding_rule" "ui" {
  count                 = var.config.general.cloud == "gcp" ? 1 : 0
  name                  = "coinops-forwarding-rule"
  target                = google_compute_target_http_proxy.ui[0].id
  port_range            = "80"
  load_balancing_scheme = "EXTERNAL"
}