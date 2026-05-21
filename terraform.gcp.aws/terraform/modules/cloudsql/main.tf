resource "google_compute_global_address" "private_ip_alloc" {
  name          = "${var.name}-cloudsql-range"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = var.private_service_range_prefix_length
  network       = var.network_id
}

resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = var.network_id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_alloc.name]
  deletion_policy         = "ABANDON"
}

resource "google_sql_database_instance" "postgres" {
  name                = "${var.name}-postgres"
  region              = var.region
  database_version    = "POSTGRES_16"
  deletion_protection = false

  settings {
    edition           = "ENTERPRISE"
    tier              = var.tier
    availability_type = "ZONAL"
    disk_size         = var.disk_size_gb
    disk_type         = "PD_SSD"
    ip_configuration {
      ipv4_enabled    = false
      private_network = var.network_id
    }
    backup_configuration {
      enabled = false
    }
  }

  depends_on = [google_service_networking_connection.private_vpc_connection]
}

resource "google_sql_database" "app" {
  name            = var.db_name
  instance        = google_sql_database_instance.postgres.name
  deletion_policy = "ABANDON"
}

resource "google_sql_user" "app" {
  name            = var.db_user
  instance        = google_sql_database_instance.postgres.name
  password        = var.db_password
  deletion_policy = "ABANDON"
}
