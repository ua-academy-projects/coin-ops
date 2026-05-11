output "database" {
  value = {
    managed         = true
    host            = google_sql_database_instance.this.private_ip_address
    endpoint        = google_sql_database_instance.this.private_ip_address
    port            = local.database.port
    name            = google_sql_database.app.name
    user            = google_sql_user.app.name
    connection_name = google_sql_database_instance.this.connection_name
  }
}
