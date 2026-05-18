data "azurerm_resource_group" "main" {
  count = var.config.general.cloud == "azure" ? 1 : 0
  name  = "coinops-rg"
}

locals {
  rg_name     = try(data.azurerm_resource_group.main[0].name, "")
  rg_location = try(data.azurerm_resource_group.main[0].location, "")
}

resource "azurerm_subnet" "db" {
  count                = var.config.general.cloud == "azure" ? 1 : 0
  name                 = "coinops-db-subnet"
  resource_group_name  = local.rg_name
  virtual_network_name = var.vnet_name
  address_prefixes     = ["10.0.3.0/24"]

  delegation {
    name = "postgres-delegation"
    service_delegation {
      name = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action"
      ]
    }
  }
}

resource "azurerm_private_dns_zone" "postgres" {
  count               = var.config.general.cloud == "azure" ? 1 : 0
  name                = "coinops.postgres.database.azure.com"
  resource_group_name = local.rg_name
}

resource "azurerm_private_dns_zone_virtual_network_link" "postgres" {
  count                 = var.config.general.cloud == "azure" ? 1 : 0
  name                  = "coinops-dns-link"
  private_dns_zone_name = azurerm_private_dns_zone.postgres[0].name
  virtual_network_id    = var.vnet_id
  resource_group_name   = local.rg_name
}

resource "azurerm_postgresql_flexible_server" "main" {
  count                  = var.config.general.cloud == "azure" ? 1 : 0
  name                   = "coinops-db"
  resource_group_name    = local.rg_name
  location               = local.rg_location
  version                = "16"
  delegated_subnet_id    = azurerm_subnet.db[0].id
  private_dns_zone_id    = azurerm_private_dns_zone.postgres[0].id
  administrator_login    = "cognitor"
  administrator_password = var.config.general.db_password
  storage_mb             = 32768
  sku_name               = "B_Standard_B1ms"
  zone                   = "1"

  depends_on = [azurerm_private_dns_zone_virtual_network_link.postgres]
}

resource "azurerm_postgresql_flexible_server_database" "main" {
  count     = var.config.general.cloud == "azure" ? 1 : 0
  name      = "cognitor"
  server_id = azurerm_postgresql_flexible_server.main[0].id
}