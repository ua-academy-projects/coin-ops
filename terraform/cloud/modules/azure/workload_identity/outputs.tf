output "client_id" {
  value = azurerm_user_assigned_identity.this.client_id
}

output "tenant_id" {
  value = data.azurerm_client_config.current.tenant_id
}

output "principal_id" {
  value = azurerm_user_assigned_identity.this.principal_id
}
