output "db_endpoint" {
  description = "PostgreSQL Flexible Server FQDN"
  value       = try(azurerm_postgresql_flexible_server.main[0].fqdn, null)
}

output "db_name" {
  description = "Database name"
  value       = try(azurerm_postgresql_flexible_server_database.main[0].name, null)
}