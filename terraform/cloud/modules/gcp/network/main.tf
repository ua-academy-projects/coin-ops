# main.tf

resource "google_compute_network" "coinops" {
  name                    = var.network.name
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
}

resource "google_compute_subnetwork" "coinops" {
  for_each = local.subnets

  name          = "${var.network.name}-${each.key}"
  ip_cidr_range = each.value.cidr
  region        = each.value.location
  network       = google_compute_network.coinops.id
}
