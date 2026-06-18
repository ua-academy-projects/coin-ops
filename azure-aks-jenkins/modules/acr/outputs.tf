output "id" {
  value = azurerm_container_registry.dev.id
}

output "name" {
  value = azurerm_container_registry.dev.name
}

output "login_server" {
  value = azurerm_container_registry.dev.login_server
}

output "admin_username" {
  value = azurerm_container_registry.dev.admin_username
}

output "admin_password" {
  value     = azurerm_container_registry.dev.admin_password
  sensitive = true
}
