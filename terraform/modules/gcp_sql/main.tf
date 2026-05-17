# Enable private services access for CloudSQL
resource "google_compute_global_address" "private_ip" {
  count         = var.config.general.cloud == "gcp" ? 1 : 0
  name          = "coinops-private-ip"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = var.network_id
}

resource "google_service_networking_connection" "private_vpc" {
  count                   = var.config.general.cloud == "gcp" ? 1 : 0
  network                 = var.network_id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip[0].name]
}

# CloudSQL PostgreSQL instance
resource "google_sql_database_instance" "postgres" {
  count            = var.config.general.cloud == "gcp" ? 1 : 0
  name             = "coinops-db"
  database_version = "POSTGRES_16"
  region           = var.config.locations[var.config.general.location].gcp.region

  deletion_protection = false

  settings {
    tier = "db-f1-micro"

    ip_configuration {
      ipv4_enabled                                  = false
      private_network                               = var.network_id
      enable_private_path_for_google_cloud_services = true
    }
  }

  depends_on = [google_service_networking_connection.private_vpc]
}

# Database
resource "google_sql_database" "main" {
  count    = var.config.general.cloud == "gcp" ? 1 : 0
  name     = "cognitor"
  instance = google_sql_database_instance.postgres[0].name
}

# Database user
resource "google_sql_user" "main" {
  count    = var.config.general.cloud == "gcp" ? 1 : 0
  name     = "cognitor"
  instance = google_sql_database_instance.postgres[0].name
  password = var.config.general.db_password
}