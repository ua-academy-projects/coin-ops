resource "google_compute_route" "nat_route" {
  name        = var.name
  network     = var.network_id
  dest_range  = var.destination_cidr
  priority    = var.priority
  tags        = var.target_tags
  next_hop_ip = var.next_hop_ip
}
