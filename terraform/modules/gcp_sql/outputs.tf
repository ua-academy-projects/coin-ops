output "db_endpoint" {
  description = "Private IP of CloudSQL instance"
  value       = try(google_sql_database_instance.postgres[0].private_ip_address, null)
}

output "db_name" {
  description = "Database name"
  value       = try(google_sql_database.main[0].name, null)
}