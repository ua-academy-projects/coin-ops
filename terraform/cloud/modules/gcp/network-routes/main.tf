resource "google_compute_route" "nat_default_egress" {
  name             = var.route_name
  network          = var.network_name
  dest_range       = var.destination_range
  priority         = 1000
  tags             = var.target_tags
  next_hop_instance = var.next_hop_instance
}
