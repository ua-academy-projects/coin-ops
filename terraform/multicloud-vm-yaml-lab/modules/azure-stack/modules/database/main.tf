resource "azurerm_private_dns_zone" "postgres" {
  name                = "privatelink.postgres.database.azure.com"
  resource_group_name = var.resource_group_name
}

resource "azurerm_private_dns_zone_virtual_network_link" "postgres" {
  name                  = "${var.name_prefix}-postgres-link"
  private_dns_zone_name = azurerm_private_dns_zone.postgres.name
  virtual_network_id    = var.network_id
  resource_group_name   = var.resource_group_name
}

resource "azurerm_postgresql_flexible_server" "this" {
  name                          = "${var.safe_prefix}-${var.unique_suffix}-postgres"
  location                      = var.location
  resource_group_name           = var.resource_group_name
  version                       = tostring(var.runtime.database.version)
  delegated_subnet_id           = var.database_subnet_id
  private_dns_zone_id           = azurerm_private_dns_zone.postgres.id
  public_network_access_enabled = false
  administrator_login           = var.runtime.database.user
  administrator_password        = var.db_password
  zone                          = var.zones[0]
  storage_mb                    = max(32768, try(var.runtime.database.storage_gb, 20) * 1024)
  sku_name                      = var.runtime.database.azure_sku_name

  depends_on = [
    azurerm_private_dns_zone_virtual_network_link.postgres,
  ]
}

resource "azurerm_postgresql_flexible_server_database" "app" {
  name      = var.runtime.database.name
  server_id = azurerm_postgresql_flexible_server.this.id
  charset   = "UTF8"
  collation = "en_US.utf8"
}
