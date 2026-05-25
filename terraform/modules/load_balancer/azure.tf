# ═════════════════════════════════════════════════════════════════════════════
# AZURE APPLICATION GATEWAY (L7 Load Balancer)
# ═════════════════════════════════════════════════════════════════════════════

locals {
  vnet_name = var.cloud_provider == "azure" ? split("/", var.vpc_id)[8] : ""

  # For Application Gateway we need a dedicated subnet. 
  # We assume the VNet has 10.10.0.0/16 and 10.10.254.0/24 is free.
}

resource "azurerm_subnet" "appgw" {
  count                = var.cloud_provider == "azure" ? 1 : 0
  name                 = "${var.name}-appgw-subnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = local.vnet_name
  address_prefixes     = [cidrsubnet(var.vpc_cidr, 8, 254)]
}

resource "azurerm_public_ip" "appgw" {
  count               = var.cloud_provider == "azure" ? 1 : 0
  name                = "${var.name}-pip"
  resource_group_name = var.resource_group_name
  location            = var.region
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.common_tags
}

resource "azurerm_application_gateway" "main" {
  count               = var.cloud_provider == "azure" ? 1 : 0
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.region

  sku {
    name     = "Standard_v2"
    tier     = "Standard_v2"
    capacity = 2
  }

  gateway_ip_configuration {
    name      = "my-gateway-ip-configuration"
    subnet_id = azurerm_subnet.appgw[0].id
  }

  frontend_port {
    name = "frontend-port-http"
    port = 80
  }

  frontend_ip_configuration {
    name                 = "frontend-ip-configuration"
    public_ip_address_id = azurerm_public_ip.appgw[0].id
  }

  backend_address_pool {
    name = "backend-pool"
  }

  backend_http_settings {
    name                                = "backend-http-settings"
    cookie_based_affinity               = "Disabled"
    path                                = "/"
    port                                = values(var.backends)[0].port
    protocol                            = "Http"
    request_timeout                     = var.health_check.timeout_sec
    probe_name                          = "health-probe"
    pick_host_name_from_backend_address = true
  }

  probe {
    name                                      = "health-probe"
    protocol                                  = title(lower(var.health_check.protocol))
    path                                      = var.health_check.path
    interval                                  = var.health_check.interval_sec
    timeout                                   = var.health_check.timeout_sec
    unhealthy_threshold                       = var.health_check.unhealthy_threshold
    pick_host_name_from_backend_http_settings = true
  }

  http_listener {
    name                           = "http-listener"
    frontend_ip_configuration_name = "frontend-ip-configuration"
    frontend_port_name             = "frontend-port-http"
    protocol                       = "Http"
  }

  request_routing_rule {
    name                       = "routing-rule-http"
    rule_type                  = "Basic"
    http_listener_name         = "http-listener"
    backend_address_pool_name  = "backend-pool"
    backend_http_settings_name = "backend-http-settings"
    priority                   = 100
  }

  tags = var.common_tags
}

# Attach NICs to Backend Pool
resource "azurerm_network_interface_application_gateway_backend_address_pool_association" "this" {
  for_each = var.cloud_provider == "azure" ? var.backends : {}

  network_interface_id    = var.instance_ids[each.key] # In compute module we need to output NIC IDs. We output instance IDs, but in Azure instance ID is the VM ID, not NIC.
  ip_configuration_name   = "internal"
  backend_address_pool_id = tolist(azurerm_application_gateway.main[0].backend_address_pool)[0].id
}
