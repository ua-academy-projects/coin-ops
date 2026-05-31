# locals.tf

locals {
  route = {
    name              = var.route.name
    destination_range = var.route.destination_range
    target_tags       = var.route.target_tags
    next_hop_instance = var.next_hop_instances[var.route.instance_workload]
  }
}
