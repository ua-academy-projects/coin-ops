data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "this" {
  name                          = var.key_vault_name
  location                      = var.location
  resource_group_name           = var.resource_group_name
  tenant_id                     = var.tenant_id
  sku_name                      = "standard"
  soft_delete_retention_days    = 7
  purge_protection_enabled      = false
  public_network_access_enabled = true

  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    secret_permissions = [
      "Get",
      "List",
      "Set",
      "Delete",
      "Recover",
      "Purge"
    ]
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_key_vault_secret" "db_secrets" {
  name = var.db_secret_name
  value = jsonencode({
    DB_PASSWORD       = var.db_password
    RABBITMQ_PASSWORD = var.rabbitmq_password
  })
  key_vault_id = azurerm_key_vault.this.id
}

resource "azurerm_key_vault_secret" "app_secrets" {
  name = var.app_secret_name
  value = jsonencode({
    GHCR_TOKEN           = var.ghcr_token
    CLOUDFLARE_API_TOKEN = var.cloudflare_api_token
    TAILSCALE_AUTH_KEY   = var.tailscale_auth_key
  })
  key_vault_id = azurerm_key_vault.this.id
}
