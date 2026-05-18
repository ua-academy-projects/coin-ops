output "key_vault_id" {
  value = data.azurerm_key_vault.this.id
}

output "secret_ids" {
  value = {
    for key, secret in var.secrets : key => secret.secret_id
  }
}
