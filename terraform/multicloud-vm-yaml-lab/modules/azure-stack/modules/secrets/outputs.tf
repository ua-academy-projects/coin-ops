locals {
  refs = {
    for key, name in local.secret_item_names : key => {
      provider   = "azure"
      name       = name
      arn        = azurerm_key_vault.this.vault_uri
      secret_id  = name
      id         = "${azurerm_key_vault.this.vault_uri}secrets/${name}"
      vault_name = azurerm_key_vault.this.name
    }
  }
}

output "refs" {
  value = local.refs
}

output "key_vault_name" {
  value = azurerm_key_vault.this.name
}

output "app_gateway_identity_id" {
  value = azurerm_user_assigned_identity.app_gateway.id
}

output "api_certificate_secret_id" {
  value = azurerm_key_vault_certificate.api.versionless_secret_id
}
