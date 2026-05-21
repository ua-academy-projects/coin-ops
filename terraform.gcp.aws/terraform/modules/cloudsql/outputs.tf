output "endpoint" {
  value = google_sql_database_instance.postgres.private_ip_address
}

output "instance_name" {
  value = google_sql_database_instance.postgres.name
}
