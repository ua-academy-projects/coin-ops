locals {
  fallback_subnets = {
    internal = { cidr = "10.10.1.0/24" }
    database = { cidr = "10.10.3.0/24" }
    external = { cidr = "10.10.2.0/24", public = true }
  }
  subnets         = length(var.subnets) > 0 ? var.subnets : local.fallback_subnets
  private_subnets = { for name, cfg in local.subnets : name => cfg if !lookup(cfg, "public", false) }
  database_subnet = lookup(local.subnets, "database", null)
}

resource "azurerm_resource_group" "this" {
  name     = var.resource_group_name
  location = var.location
}

resource "azurerm_virtual_network" "this" {
  name                = var.vpc_name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  address_space       = [var.vpc_cidr]
}

resource "time_sleep" "after_virtual_network" {
  create_duration = "20s"

  depends_on = [azurerm_virtual_network.this]
}

resource "azurerm_subnet" "this" {
  for_each             = local.subnets
  name                 = "${each.key}-subnet"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [each.value.cidr]
  service_endpoints    = each.key == "database" ? ["Microsoft.Storage"] : null

  dynamic "delegation" {
    for_each = each.key == "database" ? [1] : []
    content {
      name = "postgres-flexible"

      service_delegation {
        name    = "Microsoft.DBforPostgreSQL/flexibleServers"
        actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
      }
    }
  }

  depends_on = [time_sleep.after_virtual_network]
}

resource "time_sleep" "after_subnets" {
  create_duration = "20s"

  depends_on = [azurerm_subnet.this]
}
