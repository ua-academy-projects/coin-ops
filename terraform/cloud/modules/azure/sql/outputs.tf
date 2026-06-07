# outputs.tf

output "instance_name" {
  value = azurerm_postgresql_flexible_server.this.name
}

output "private_endpoint" {
  value = azurerm_postgresql_flexible_server.this.fqdn
}

output "connection_name" {
  value = azurerm_postgresql_flexible_server.this.fqdn
}

output "database_name" {
  value = azurerm_postgresql_flexible_server_database.this.name
}

output "database_user" {
  value = var.user.name
}

output "server_id" {
  value = azurerm_postgresql_flexible_server.this.id
}
