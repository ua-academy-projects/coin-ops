output "instance_name" {
  value = azurerm_postgresql_flexible_server.this.name
}

output "private_fqdn" {
  value = azurerm_postgresql_flexible_server.this.fqdn
}

output "database_name" {
  value = azurerm_postgresql_flexible_server_database.this.name
}

output "database_user" {
  value = var.user.name
}
