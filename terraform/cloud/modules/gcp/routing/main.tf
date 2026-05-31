# main.tf

resource "google_compute_route" "nat_default_egress" {
  name              = local.route.name
  network           = var.network_name
  dest_range        = local.route.destination_range
  priority          = 1000
  tags              = local.route.target_tags
  next_hop_instance = local.route.next_hop_instance
}
