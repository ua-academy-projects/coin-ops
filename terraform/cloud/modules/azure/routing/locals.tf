locals {
  route = {
    name              = var.route.name
    destination_range = var.route.destination_range
    next_hop_ip       = var.route.next_hop_ip
  }
}
