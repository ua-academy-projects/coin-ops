# ═════════════════════════════════════════════════════════════════════════════
# GCP LOAD BALANCER (Global HTTP/HTTPS Load Balancer)
# ═════════════════════════════════════════════════════════════════════════════

# ─── Unmanaged Instance Groups (One per zone) ───────────────────────────────
resource "google_compute_instance_group" "this" {
  for_each = var.cloud_provider == "gcp" ? local.backends_by_zone : {}

  name        = "${var.name}-ig-${each.key}"
  zone        = each.key
  project     = var.gcp_project_id
  description = "Unmanaged instance group for ${var.name} in ${each.key}"

  instances = [
    for inst_name in each.value : var.instance_self_links[inst_name]
  ]

  # Using the first backend's port for the named port, assuming all backends in the group use the same port
  named_port {
    name = "http"
    port = var.backends[each.value[0]].port
  }
}

# ─── Health Check ────────────────────────────────────────────────────────────
resource "google_compute_health_check" "this" {
  count = var.cloud_provider == "gcp" ? 1 : 0

  name                = "${var.name}-hc"
  project             = var.gcp_project_id
  check_interval_sec  = var.health_check.interval_sec
  timeout_sec         = var.health_check.timeout_sec
  healthy_threshold   = var.health_check.healthy_threshold
  unhealthy_threshold = var.health_check.unhealthy_threshold

  dynamic "http_health_check" {
    for_each = upper(var.health_check.protocol) == "HTTP" ? [1] : []
    content {
      port         = var.health_check.port
      request_path = var.health_check.path
    }
  }

  dynamic "tcp_health_check" {
    for_each = upper(var.health_check.protocol) == "TCP" ? [1] : []
    content {
      port = var.health_check.port
    }
  }
}

# ─── Backend Service ─────────────────────────────────────────────────────────
resource "google_compute_backend_service" "this" {
  count = var.cloud_provider == "gcp" ? 1 : 0

  name                  = "${var.name}-backend"
  project               = var.gcp_project_id
  protocol              = "HTTP"
  port_name             = "http"
  load_balancing_scheme = "EXTERNAL"
  health_checks         = [google_compute_health_check.this[0].id]

  dynamic "backend" {
    for_each = google_compute_instance_group.this
    content {
      group = backend.value.id
    }
  }
}

# ─── URL Map ─────────────────────────────────────────────────────────────────
resource "google_compute_url_map" "this" {
  count = var.cloud_provider == "gcp" ? 1 : 0

  name            = "${var.name}-url-map"
  project         = var.gcp_project_id
  default_service = google_compute_backend_service.this[0].id
}

# ─── Target Proxy & Forwarding Rule (HTTP) ──────────────────────────────────
resource "google_compute_target_http_proxy" "this" {
  # Create if we have an HTTP listener
  for_each = var.cloud_provider == "gcp" && length([for k, v in var.listeners : k if upper(v.protocol) == "HTTP"]) > 0 ? { http = true } : {}

  name    = "${var.name}-http-proxy"
  project = var.gcp_project_id
  url_map = google_compute_url_map.this[0].id
}

resource "google_compute_global_forwarding_rule" "http" {
  for_each = google_compute_target_http_proxy.this

  name                  = "${var.name}-http-rule"
  project               = var.gcp_project_id
  ip_address            = var.ip_address
  target                = each.value.id
  port_range            = "80"
  load_balancing_scheme = "EXTERNAL"
}

# ─── Managed SSL Certificate & HTTPS Proxy (HTTPS) ──────────────────────────
resource "google_compute_managed_ssl_certificate" "this" {
  count = var.cloud_provider == "gcp" && length(var.domains) > 0 ? 1 : 0

  name    = "${var.name}-cert-v3"
  project = var.gcp_project_id

  managed {
    domains = var.domains
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "google_compute_target_https_proxy" "this" {
  for_each = var.cloud_provider == "gcp" && length([for k, v in var.listeners : k if upper(v.protocol) == "HTTPS"]) > 0 && length(var.domains) > 0 ? { https = true } : {}

  name             = "${var.name}-https-proxy"
  project          = var.gcp_project_id
  url_map          = google_compute_url_map.this[0].id
  ssl_certificates = [google_compute_managed_ssl_certificate.this[0].id]
}

resource "google_compute_global_forwarding_rule" "https" {
  for_each = google_compute_target_https_proxy.this

  name                  = "${var.name}-https-rule"
  project               = var.gcp_project_id
  ip_address            = var.ip_address
  target                = each.value.id
  port_range            = "443"
  load_balancing_scheme = "EXTERNAL"
}
