locals {
  database = var.runtime.database
}

resource "google_compute_global_address" "private_service_range" {
  name          = "${var.name_prefix}-sql-private-range"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = var.network_self_link
}

resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = var.network_self_link
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_service_range.name]
}

resource "google_sql_database_instance" "this" {
  name             = "${var.name_prefix}-postgres"
  database_version = local.database.gcp_database_version
  region           = var.region

  deletion_protection = false

  settings {
    tier      = local.database.gcp_tier
    disk_size = local.database.storage_gb
    disk_type = "PD_SSD"

    backup_configuration {
      enabled = true
    }

    ip_configuration {
      ipv4_enabled    = false
      private_network = var.network_self_link
    }
  }

  depends_on = [google_service_networking_connection.private_vpc_connection]
}

resource "google_sql_database" "app" {
  name     = local.database.name
  instance = google_sql_database_instance.this.name
}

resource "google_sql_user" "app" {
  name     = local.database.user
  instance = google_sql_database_instance.this.name
  password = var.db_password
}
