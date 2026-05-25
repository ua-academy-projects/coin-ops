resource "google_sql_database_instance" "postgres" {
  count = var.cloud_provider == "gcp" ? 1 : 0

  name             = "coinops-postgres"
  database_version = "POSTGRES_${var.db_engine_version}"
  region           = var.region

  settings {
    tier              = var.db_instance_class
    availability_type = var.multi_az ? "REGIONAL" : "ZONAL"
    disk_size         = var.db_allocated_storage
    disk_type         = var.db_storage_type

    ip_configuration {
      ipv4_enabled    = false
      private_network = var.vpc_id
    }

    backup_configuration {
      enabled                        = true
      start_time                     = "02:00"
      point_in_time_recovery_enabled = true

      backup_retention_settings {
        retained_backups = var.backup_retention_days
        retention_unit   = "COUNT"
      }
    }
  }

  deletion_protection = var.deletion_protection

  depends_on = [google_service_networking_connection.private_vpc_connection]
}

resource "google_service_networking_connection" "private_vpc_connection" {
  count = var.cloud_provider == "gcp" ? 1 : 0

  network                 = var.vpc_id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_address[0].name]
}

resource "google_compute_global_address" "private_ip_address" {
  count = var.cloud_provider == "gcp" ? 1 : 0

  name          = "coinops-postgres-private-ip"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = var.vpc_id
}

resource "google_sql_database" "postgres" {
  count = var.cloud_provider == "gcp" ? 1 : 0

  name     = var.db_name
  instance = google_sql_database_instance.postgres[0].name
}

resource "google_sql_user" "postgres" {
  count = var.cloud_provider == "gcp" ? 1 : 0

  name     = var.db_username
  instance = google_sql_database_instance.postgres[0].name
  password = random_password.db_password.result
}



