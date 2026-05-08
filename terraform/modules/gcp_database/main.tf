# Private Service Access for CloudSQL (VPC Peering)
resource "google_compute_global_address" "private_ip_alloc" {
  name          = "${var.project_name}-db-ip-alloc"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = var.network_id
}

resource "google_service_networking_connection" "default" {
  network                 = var.network_id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_alloc.name]
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
    tier = var.db_tier
    
    ip_configuration {
      ipv4_enabled    = false
      private_network = var.network_id
    }
    
    # Cost optimization for dev
    disk_type = "PD_HDD"
    disk_size = 10
  }
  
  deletion_protection = var.deletion_protection
}

# The actual database
resource "google_sql_database" "cognitor" {
  name     = "cognitor"
  instance = google_sql_database_instance.main.name
}

# Database User
resource "google_sql_user" "cognitor_user" {
  name            = "cognitor"
  instance        = google_sql_database_instance.main.name
  password        = var.db_password
  deletion_policy = "ABANDON"
}
