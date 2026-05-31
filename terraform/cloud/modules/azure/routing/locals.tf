locals {
  route = {
    name              = var.route.name
    destination_range = var.route.destination_range
    next_hop_ip       = var.next_hop_private_ips[var.route.instance_workload]
  }
}
