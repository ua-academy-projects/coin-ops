locals {
  app_instance_groups = {
    for zone in distinct([for _, instance in var.app_instances : instance.zone]) : zone => [
      for _, instance in var.app_instances : instance.self_link if instance.zone == zone
    ]
  }
}

resource "google_compute_instance_group" "app" {
  for_each = local.app_instance_groups

  name      = "${var.name_prefix}-${each.key}-app-ig"
  zone      = each.key
  instances = each.value

  named_port {
    name = "http"
    port = var.app_port
  }
}

resource "google_compute_health_check" "app" {
  name = "${var.name_prefix}-app-health"

  http_health_check {
    port         = var.app_port
    request_path = var.health_path
  }
}

resource "google_compute_backend_service" "app" {
  name                  = "${var.name_prefix}-app-backend"
  protocol              = "HTTP"
  port_name             = "http"
  load_balancing_scheme = "EXTERNAL"
  timeout_sec           = 30
  health_checks         = [google_compute_health_check.app.self_link]

  dynamic "backend" {
    for_each = google_compute_instance_group.app
    content {
      group = backend.value.self_link
    }
  }
}

resource "google_compute_url_map" "app" {
  name            = "${var.name_prefix}-app-url-map"
  default_service = google_compute_backend_service.app.self_link
}

resource "google_compute_target_https_proxy" "app" {
  count = var.domain_enabled ? 1 : 0

  name             = "${var.name_prefix}-https-proxy"
  url_map          = google_compute_url_map.app.self_link
  ssl_certificates = [var.certificate_self_link]
}

resource "google_compute_global_forwarding_rule" "https" {
  count = var.domain_enabled ? 1 : 0

  name                  = "${var.name_prefix}-https"
  ip_address            = var.ip_address
  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL"
  port_range            = "443"
  target                = google_compute_target_https_proxy.app[0].self_link
}

resource "google_compute_url_map" "http_redirect" {
  count = var.domain_enabled ? 1 : 0

  name = "${var.name_prefix}-http-redirect"

  default_url_redirect {
    https_redirect = true
    strip_query    = false
  }
}

resource "google_compute_target_http_proxy" "http_redirect" {
  count = var.domain_enabled ? 1 : 0

  name    = "${var.name_prefix}-http-redirect-proxy"
  url_map = google_compute_url_map.http_redirect[0].self_link
}

resource "google_compute_global_forwarding_rule" "http_redirect" {
  count = var.domain_enabled ? 1 : 0

  name                  = "${var.name_prefix}-http-redirect"
  ip_address            = var.ip_address
  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL"
  port_range            = "80"
  target                = google_compute_target_http_proxy.http_redirect[0].self_link
}

resource "google_compute_target_http_proxy" "http_fallback" {
  count = var.domain_enabled ? 0 : 1

  name    = "${var.name_prefix}-http-proxy"
  url_map = google_compute_url_map.app.self_link
}

resource "google_compute_global_forwarding_rule" "http_fallback" {
  count = var.domain_enabled ? 0 : 1

  name                  = "${var.name_prefix}-http"
  ip_address            = var.ip_address
  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL"
  port_range            = "80"
  target                = google_compute_target_http_proxy.http_fallback[0].self_link
}
