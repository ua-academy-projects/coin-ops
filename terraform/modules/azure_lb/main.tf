data "azurerm_resource_group" "main" {
  count = var.config.general.cloud == "azure" ? 1 : 0
  name  = "coinops-rg"
}

locals {
  rg_name     = try(data.azurerm_resource_group.main[0].name, "")
  rg_location = try(data.azurerm_resource_group.main[0].location, "")
}

resource "azurerm_public_ip" "lb" {
  count               = var.config.general.cloud == "azure" ? 1 : 0
  name                = "coinops-lb-pip"
  location            = local.rg_location
  resource_group_name = local.rg_name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_lb" "main" {
  count               = var.config.general.cloud == "azure" ? 1 : 0
  name                = "coinops-lb"
  location            = local.rg_location
  resource_group_name = local.rg_name
  sku                 = "Standard"

  frontend_ip_configuration {
    name                 = "coinops-frontend"
    public_ip_address_id = azurerm_public_ip.lb[0].id
  }
}

resource "azurerm_lb_backend_address_pool" "main" {
  count           = var.config.general.cloud == "azure" ? 1 : 0
  name            = "coinops-backend-pool"
  loadbalancer_id = azurerm_lb.main[0].id
}

resource "azurerm_lb_probe" "http" {
  count               = var.config.general.cloud == "azure" ? 1 : 0
  name                = "coinops-http-probe"
  loadbalancer_id     = azurerm_lb.main[0].id
  protocol            = "Http"
  port                = 80
  request_path        = "/health"
  interval_in_seconds = 15
  number_of_probes    = 2
}

resource "azurerm_lb_rule" "http" {
  count                          = var.config.general.cloud == "azure" ? 1 : 0
  name                           = "coinops-http-rule"
  loadbalancer_id                = azurerm_lb.main[0].id
  protocol                       = "Tcp"
  frontend_port                  = 80
  backend_port                   = 80
  frontend_ip_configuration_name = "coinops-frontend"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.main[0].id]
  probe_id                       = azurerm_lb_probe.http[0].id
}

resource "azurerm_network_interface_backend_address_pool_association" "ui" {
  count                   = var.config.general.cloud == "azure" ? 1 : 0
  network_interface_id    = var.ui_nic_id
  ip_configuration_name   = "internal"
  backend_address_pool_id = azurerm_lb_backend_address_pool.main[0].id
}