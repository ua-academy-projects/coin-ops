# ----------------------------------------------------------------------------
# VPC Network
# ----------------------------------------------------------------------------
resource "google_compute_network" "this" {
  name                    = var.name
  project                 = var.project_id
  auto_create_subnetworks = false
  description             = var.description
}

# ----------------------------------------------------------------------------
# Subnets — created dynamically from input map
# ----------------------------------------------------------------------------
resource "google_compute_subnetwork" "this" {
  for_each = var.subnets

  name          = each.key
  project       = var.project_id
  network       = google_compute_network.this.id
  ip_cidr_range = each.value.cidr
  region        = each.value.region
}
