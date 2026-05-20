locals {
  https_enabled = var.ssl_certificate_key_vault_secret_id != ""
  backend_ips   = [for instance in values(var.app_instances) : instance.private_ip]
  probe_host    = var.api_domain != "" ? var.api_domain : "127.0.0.1"
}

resource "azurerm_public_ip" "api" {
  name                = "${var.name_prefix}-api-ip"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_application_gateway" "api" {
  name                = "${var.name_prefix}-api-appgw"
  location            = var.location
  resource_group_name = var.resource_group_name

  identity {
    type         = "UserAssigned"
    identity_ids = [var.gateway_identity_id]
  }

  sku {
    name     = "Standard_v2"
    tier     = "Standard_v2"
    capacity = 1
  }

  gateway_ip_configuration {
    name      = "gateway"
    subnet_id = var.gateway_subnet_id
  }

  frontend_ip_configuration {
    name                 = "public"
    public_ip_address_id = azurerm_public_ip.api.id
  }

  frontend_port {
    name = "http"
    port = 80
  }

  dynamic "frontend_port" {
    for_each = local.https_enabled ? [1] : []

    content {
      name = "https"
      port = 443
    }
  }

  backend_address_pool {
    name         = "${var.name_prefix}-api-backends"
    ip_addresses = local.backend_ips
  }

  probe {
    name                = "http-health"
    protocol            = "Http"
    host                = local.probe_host
    path                = var.health_path
    interval            = 30
    timeout             = 30
    unhealthy_threshold = 3
  }

  backend_http_settings {
    name                  = "http"
    cookie_based_affinity = "Disabled"
    port                  = var.app_port
    protocol              = "Http"
    request_timeout       = 30
    probe_name            = "http-health"
  }

  http_listener {
    name                           = "http"
    frontend_ip_configuration_name = "public"
    frontend_port_name             = "http"
    protocol                       = "Http"
  }

  dynamic "ssl_certificate" {
    for_each = local.https_enabled ? [1] : []

    content {
      name                = "api"
      key_vault_secret_id = var.ssl_certificate_key_vault_secret_id
    }
  }

  dynamic "http_listener" {
    for_each = local.https_enabled ? [1] : []

    content {
      name                           = "https"
      frontend_ip_configuration_name = "public"
      frontend_port_name             = "https"
      protocol                       = "Https"
      ssl_certificate_name           = "api"
    }
  }

  dynamic "redirect_configuration" {
    for_each = local.https_enabled ? [1] : []

    content {
      name                 = "http-to-https"
      redirect_type        = "Permanent"
      target_listener_name = "https"
      include_path         = true
      include_query_string = true
    }
  }

  request_routing_rule {
    name                        = local.https_enabled ? "http-redirect" : "http"
    rule_type                   = "Basic"
    http_listener_name          = "http"
    backend_address_pool_name   = local.https_enabled ? null : "${var.name_prefix}-api-backends"
    backend_http_settings_name  = local.https_enabled ? null : "http"
    redirect_configuration_name = local.https_enabled ? "http-to-https" : null
    priority                    = 100
  }

  dynamic "request_routing_rule" {
    for_each = local.https_enabled ? [1] : []

    content {
      name                       = "https"
      rule_type                  = "Basic"
      http_listener_name         = "https"
      backend_address_pool_name  = "${var.name_prefix}-api-backends"
      backend_http_settings_name = "http"
      priority                   = 110
    }
  }
}
