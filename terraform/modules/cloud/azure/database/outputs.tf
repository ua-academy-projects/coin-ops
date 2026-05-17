output "fqdn" {
  value = azurerm_postgresql_flexible_server.this.fqdn
}

output "port" {
  value = var.db_port
}
