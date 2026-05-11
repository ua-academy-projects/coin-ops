output "load_balancer" {
  value = {
    dns_name         = var.ip_address
    zone_id          = null
    https_enabled    = var.domain_enabled
    target_group_arn = google_compute_backend_service.app.self_link
  }
}
