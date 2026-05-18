# Private Service Access for CloudSQL (VPC Peering)
resource "google_compute_global_address" "private_ip_alloc" {
  name          = "${var.project_name}-db-ip-alloc"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = var.network_id

  lifecycle {
    prevent_destroy = true
  }
}

resource "google_service_networking_connection" "default" {
  network                 = var.network_id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_alloc.name]

  lifecycle {
    prevent_destroy = true
  }
}

# Generate a random suffix to avoid name collisions on recreate
resource "random_id" "db_name_suffix" {
  byte_length = 4
}

# CloudSQL Instance
resource "google_sql_database_instance" "main" {
  name             = "${var.project_name}-db-${random_id.db_name_suffix.hex}"
  region           = var.region
  database_version = "POSTGRES_16"

  depends_on = [google_service_networking_connection.default]

  settings {
    edition = var.edition
    tier    = var.db_tier

    ip_configuration {
      ipv4_enabled    = false
      private_network = var.network_id
    }

    disk_type = var.disk_type
    disk_size = var.disk_size
  }

  deletion_protection = true

  lifecycle {
    prevent_destroy = true
  }
}

# The actual database
resource "google_sql_database" "cognitor" {
  name     = var.db_name
  instance = google_sql_database_instance.main.name

  lifecycle {
    prevent_destroy = true
  }
}

# Database User
resource "google_sql_user" "cognitor_user" {
  name            = var.db_username
  instance        = google_sql_database_instance.main.name
  password        = var.db_password
  deletion_policy = "ABANDON"

  lifecycle {
    prevent_destroy = true
  }
}
