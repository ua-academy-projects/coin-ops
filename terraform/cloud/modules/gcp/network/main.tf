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

resource "google_compute_route" "nat_default_egress" {
  count = var.nat_route == null ? 0 : 1

  name                   = var.nat_route.name
  network                = google_compute_network.coinops.name
  dest_range             = var.nat_route.destination_range
  priority               = 1000
  tags                   = var.nat_route.target_tags
  next_hop_instance      = var.nat_route.next_hop_instance
  next_hop_instance_zone = var.nat_route.next_hop_zone
}
