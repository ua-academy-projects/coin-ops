resource "azurerm_role_assignment" "key_vault_secrets_user" {
  for_each = local.access_bindings

  scope                = data.azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = each.value.principal_id
}
