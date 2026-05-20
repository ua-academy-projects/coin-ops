output "database" {
  value = {
    managed = true
    backend = "postgres"
    host    = azurerm_postgresql_flexible_server.this.fqdn
    port    = 5432
    name    = azurerm_postgresql_flexible_server_database.app.name
    user    = azurerm_postgresql_flexible_server.this.administrator_login
  }
}
