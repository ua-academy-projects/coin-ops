output "private_ip" {
  description = "The private IP address of the CloudSQL instance"
  value       = google_sql_database_instance.main.private_ip_address
}

output "connection_name" {
  description = "The connection name of the CloudSQL instance to be used in connection strings"
  value       = google_sql_database_instance.main.connection_name
}
