# locals.tf

locals {
  route = {
    name                  = var.route.name
    destination_range     = var.route.destination_range
    next_hop_interface_id = var.next_hop_interface_ids[var.route.instance_workload]
  }
}
