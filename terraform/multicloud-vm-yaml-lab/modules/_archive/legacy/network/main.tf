resource "google_compute_network" "main" {
  name                    = var.network.name
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "main" {
  name          = var.network.subnet_name
  ip_cidr_range = var.network.cidr
  region        = var.region
  network       = google_compute_network.main.id
}
