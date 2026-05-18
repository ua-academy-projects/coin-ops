data "azurerm_resource_group" "this" {
  name = var.resource_group_name
}

data "azurerm_key_vault" "this" {
  name                = var.key_vault_name
  resource_group_name = data.azurerm_resource_group.this.name
}

data "azurerm_key_vault_secret" "db_password" {
  name         = var.db_password_secret_id
  key_vault_id = data.azurerm_key_vault.this.id
}
