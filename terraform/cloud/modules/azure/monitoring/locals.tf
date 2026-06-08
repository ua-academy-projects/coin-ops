locals {
  frontend_base_url = var.frontend_public_ip != null ? "http://${var.frontend_public_ip}" : null

  availability_tests = var.http_availability_tests_enabled && local.frontend_base_url != null ? {
    frontend = "${local.frontend_base_url}/health"
    proxy    = "${local.frontend_base_url}/api/health"
    history  = "${local.frontend_base_url}/history-api/health"
  } : {}
}
