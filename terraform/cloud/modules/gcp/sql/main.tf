data "google_client_config" "current" {}

data "google_secret_manager_secret_version" "db_password" {
  secret  = var.db_password_secret_id
  version = "latest"
}

resource "google_compute_global_address" "this" {
  name          = local.instance.private_range_name
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = local.instance.private_range_cidr
  network       = "projects/${data.google_client_config.current.project}/global/networks/${var.network_name}"
}

resource "google_service_networking_connection" "this" {
  network                 = "projects/${data.google_client_config.current.project}/global/networks/${var.network_name}"
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.this.name]
}

resource "google_sql_database_instance" "this" {
  name             = local.instance.name
  region           = local.region
  database_version = local.instance.database_version
  depends_on       = [google_service_networking_connection.this]

  settings {
    edition                     = local.instance.edition
    tier                        = local.instance.tier
    availability_type           = local.instance.availability_type
    disk_type                   = local.instance.disk_type
    disk_size                   = local.instance.disk_size
    disk_autoresize             = local.instance.disk_autoresize
    deletion_protection_enabled = local.instance.deletion_protection_enabled

    backup_configuration {
      enabled                        = local.instance.backup_enabled
      point_in_time_recovery_enabled = local.instance.pitr_enabled
    }

    ip_configuration {
      ipv4_enabled    = false
      private_network = "projects/${data.google_client_config.current.project}/global/networks/${var.network_name}"
    }
  }
}

resource "google_sql_database" "this" {
  name     = var.database.name
  instance = google_sql_database_instance.this.name
}

resource "google_sql_user" "this" {
  name     = var.user.name
  instance = google_sql_database_instance.this.name
  password = data.google_secret_manager_secret_version.db_password.secret_data
}
