# ═════════════════════════════════════════════════════════════════════════════
# AZURE KEY VAULT
# ═════════════════════════════════════════════════════════════════════════════

data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "app_secrets" {
  count                       = var.cloud_provider == "azure" ? 1 : 0
  name                        = "coinops-kv-${substr(uuid(), 0, 8)}" # Key Vault name must be globally unique
  location                    = var.region
  resource_group_name         = var.resource_group_name
  enabled_for_disk_encryption = true
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  soft_delete_retention_days  = 7
  purge_protection_enabled    = false

  sku_name = "standard"

  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    secret_permissions = [
      "Get", "List", "Set", "Delete", "Purge"
    ]
  }

  tags = var.common_tags

  lifecycle {
    ignore_changes = [name]
  }
}

resource "azurerm_key_vault_secret" "app_secrets_version" {
  count = var.cloud_provider == "azure" ? 1 : 0
  name  = "app-secrets"
  value = jsonencode({
    DATABASE_URL      = "postgresql://${var.db_username}:${var.db_password}@${var.db_host}:5432/${var.db_name}"
    DB_PASSWORD       = var.db_password
    DB_HOST           = var.db_host
    RABBITMQ_PASSWORD = var.rabbitmq_password
  })
  key_vault_id = azurerm_key_vault.app_secrets[0].id

  depends_on = [azurerm_key_vault.app_secrets]
}
