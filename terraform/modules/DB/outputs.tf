output "db_instance_address" {
  description = "Database instance private IP address"
  value = (
    var.cloud_provider == "gcp"
    ? google_sql_database_instance.postgres[0].private_ip_address
    : (var.cloud_provider == "aws"
      ? aws_db_instance.postgres[0].address
    : azurerm_postgresql_flexible_server.this[0].fqdn)
  )
}

output "db_instance_port" {
  description = "Database instance port"
  value       = 5432
}

output "db_connection_string" {
  description = "Database connection string"
  value       = var.cloud_provider == "aws" ? "postgresql://${var.db_username}:${urlencode(random_password.db_password.result)}@${aws_db_instance.postgres[0].address}:5432/${var.db_name}" : (var.cloud_provider == "gcp" ? "postgresql://${var.db_username}:${urlencode(random_password.db_password.result)}@${google_sql_database_instance.postgres[0].private_ip_address}:5432/${var.db_name}" : "postgresql://${var.db_username}:${urlencode(random_password.db_password.result)}@${azurerm_postgresql_flexible_server.this[0].fqdn}:5432/${var.db_name}")
  sensitive   = true
}

output "db_password" {
  description = "Raw database password"
  value       = random_password.db_password.result
  sensitive   = true
}