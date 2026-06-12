resource "azurerm_subnet" "postgres" {
  name                 = "${var.instance.name}-db"
  resource_group_name  = data.azurerm_resource_group.this.name
  virtual_network_name = var.network_name
  address_prefixes     = [local.delegated_subnet_cidr]

  delegation {
    name = "postgres-flexible-server"

    service_delegation {
      name = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action",
      ]
    }
  }
}

resource "azurerm_private_dns_zone" "this" {
  name                = "${var.instance.name}.private.postgres.database.azure.com"
  resource_group_name = data.azurerm_resource_group.this.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "this" {
  name                  = "${var.instance.name}-vnet-link"
  resource_group_name   = data.azurerm_resource_group.this.name
  private_dns_zone_name = azurerm_private_dns_zone.this.name
  virtual_network_id    = var.network_id
}

resource "azurerm_postgresql_flexible_server" "this" {
  name                          = local.instance.name
  resource_group_name           = data.azurerm_resource_group.this.name
  location                      = local.location
  version                       = local.instance.database_version

  delegated_subnet_id           = azurerm_subnet.postgres.id
  private_dns_zone_id           = azurerm_private_dns_zone.this.id

  administrator_login           = var.user.name
  administrator_password        = data.azurerm_key_vault_secret.db_password.value
  zone                          = local.instance.zone
  storage_mb                    = local.instance.storage_mb
  auto_grow_enabled             = local.instance.storage_auto_grow_enabled
  sku_name                      = local.instance.sku_name
  backup_retention_days         = local.instance.backup_retention_days
  geo_redundant_backup_enabled  = local.instance.geo_redundant_backup_enabled
  public_network_access_enabled = false

  dynamic "high_availability" {
    for_each = local.instance.high_availability_mode != null ? [1] : []

    content {
      mode = local.instance.high_availability_mode
    }
  }

  depends_on = [azurerm_private_dns_zone_virtual_network_link.this]
}

resource "azurerm_postgresql_flexible_server_database" "this" {
  name      = var.database.name
  server_id = azurerm_postgresql_flexible_server.this.id
  charset   = "UTF8"
  collation = "en_US.utf8"
}
