# ═════════════════════════════════════════════════════════════════════════════
# AZURE POSTGRESQL FLEXIBLE SERVER
# ═════════════════════════════════════════════════════════════════════════════

resource "azurerm_postgresql_flexible_server" "this" {
  count = var.cloud_provider == "azure" ? 1 : 0

  name                   = "${var.db_name}-server"
  resource_group_name    = var.resource_group_name
  location               = var.region
  version                = split(".", var.db_engine_version)[0] # Extract major version, e.g. "14.1" -> "14"
  administrator_login    = var.db_username
  administrator_password = random_password.db_password.result
  storage_mb             = max(32768, var.db_allocated_storage * 1024)
  sku_name               = var.db_instance_class

  backup_retention_days = var.backup_retention_days

  dynamic "high_availability" {
    for_each = var.multi_az ? [1] : []
    content {
      mode = "ZoneRedundant"
    }
  }

  tags = var.common_tags

  lifecycle {
    ignore_changes = [
      zone,
      high_availability[0].standby_availability_zone
    ]
  }
}

resource "azurerm_postgresql_flexible_server_database" "this" {
  count = var.cloud_provider == "azure" ? 1 : 0

  name      = var.db_name
  server_id = azurerm_postgresql_flexible_server.this[0].id
  charset   = "UTF8"
  collation = "en_US.utf8"
}

# Allow traffic from all Azure internal networks. For production, restrict to vnet.
resource "azurerm_postgresql_flexible_server_firewall_rule" "allow_azure" {
  count = var.cloud_provider == "azure" ? 1 : 0

  name             = "AllowAllAzureServicesAndResourcesWithinAzureIps"
  server_id        = azurerm_postgresql_flexible_server.this[0].id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}
