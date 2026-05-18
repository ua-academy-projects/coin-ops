resource "google_compute_route" "nat_route" {
  for_each = var.routes

  name        = each.key
  network     = var.network_id
  dest_range  = each.value.destination_cidr
  priority    = lookup(each.value, "priority", 800)
  tags        = lookup(each.value, "target_tags", ["internal-vm"])
  next_hop_ip = var.next_hop_ip
}
