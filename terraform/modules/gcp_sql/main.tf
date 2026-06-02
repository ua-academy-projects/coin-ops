# Reserves a private IP range inside the GCP VPC for CloudSQL.
# CloudSQL uses this range to get a private IP — no public internet exposure.
# VPC_PEERING means CloudSQL "peers" into your VPC network privately.
resource "google_compute_global_address" "private_ip" {
  count         = var.config.general.database == "gcp" ? 1 : 0
  name          = "coinops-private-ip"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = var.network_id
}

# Creates the actual private network connection between your VPC and
# Google's managed services network. Without this, CloudSQL has no
# private IP and your k3s pods cannot reach it internally.
resource "google_service_networking_connection" "private_vpc" {
  count                   = var.config.general.database == "gcp" ? 1 : 0
  network                 = var.network_id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip[0].name]
}

# The actual CloudSQL PostgreSQL instance.
# db-f1-micro = smallest/cheapest tier (~$7/month, fits student credits).
# ipv4_enabled=false = no public IP, private VPC only — correct secure approach.
# depends_on ensures private networking exists before instance is created.
resource "google_sql_database_instance" "postgres" {
  count               = var.config.general.database == "gcp" ? 1 : 0
  name                = "coinops-db"
  database_version    = "POSTGRES_16"
  region              = var.config.locations[var.config.general.location].gcp.region
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

# Creates the "cognitor" database inside the CloudSQL instance.
resource "google_sql_database" "main" {
  count    = var.config.general.database == "gcp" ? 1 : 0
  name     = "cognitor"
  instance = google_sql_database_instance.postgres[0].name
}

# Creates the "cognitor" user with password from .env DB_PASSWORD variable.
# Password comes through terraform.tfvars → var.db_password → config.general.db_password.
resource "google_sql_user" "main" {
  count    = var.config.general.database == "gcp" ? 1 : 0
  name     = "cognitor"
  instance = google_sql_database_instance.postgres[0].name
  password = var.config.general.db_password
}