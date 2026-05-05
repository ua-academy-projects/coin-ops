locals {
  fallback_subnets = {
    internal = { cidr = "10.10.1.0/24" }
    external = { cidr = "10.10.2.0/24" }
  }
  subnets = length(var.subnets) > 0 ? var.subnets : local.fallback_subnets
}

resource "google_compute_network" "vpc" {
  name                    = var.vpc_name
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "subnet" {
  for_each      = local.subnets
  name          = "${each.key}-subnet"
  ip_cidr_range = each.value.cidr
  region        = var.region
  network       = google_compute_network.vpc.id
}
