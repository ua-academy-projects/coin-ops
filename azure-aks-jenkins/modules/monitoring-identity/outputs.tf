output "id" {
  value = azurerm_user_assigned_identity.dev.id
}

output "client_id" {
  value = azurerm_user_assigned_identity.dev.client_id
}

output "principal_id" {
  value = azurerm_user_assigned_identity.dev.principal_id
}

output "name" {
  value = azurerm_user_assigned_identity.dev.name
}
