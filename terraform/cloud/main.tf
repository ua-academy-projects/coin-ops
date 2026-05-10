# main.tf


# gcp

module "gcp_network" {
  source = "./modules/gcp/network"
  count  = var.cloud == "gcp" ? 1 : 0

  network = var.network
}


module "gcp_security" {
  source = "./modules/gcp/security"
  count  = var.cloud == "gcp" ? 1 : 0

  network_name       = module.gcp_network[0].network_name
  workload_selectors = module.gcp_instances[0].workload_selectors
  rules              = var.security_rules
}


module "gcp_instances" {
  source = "./modules/gcp/instances"
  count  = var.cloud == "gcp" ? 1 : 0

  ssh_user            = "deployer"
  ssh_public_key_path = pathexpand(var.ssh_public_key_path)
  network_name        = module.gcp_network[0].network_name
  subnetworks         = module.gcp_network[0].subnetwork_names

  workloads = var.workloads
}

module "gcp_network_routes" {
  source = "./modules/gcp/network-routes"
  count  = var.cloud == "gcp" && var.nat_route != null ? 1 : 0

  network_name      = module.gcp_network[0].network_name
  route_name        = var.nat_route.name
  destination_range = var.nat_route.destination_range
  target_tags       = var.nat_route.target_tags
  next_hop_instance = module.gcp_instances[0].instance_self_links[var.nat_route.instance_workload]
}


# aws

module "aws_network" {
  source = "./modules/aws/network"
  count  = var.cloud == "aws" ? 1 : 0

  network = var.network
}


module "aws_security" {
  source = "./modules/aws/security"
  count  = var.cloud == "aws" ? 1 : 0

  network_id     = module.aws_network[0].network_id
  workload_names = keys(var.workloads)
  rules          = var.security_rules
}


module "aws_instances" {
  source = "./modules/aws/instances"
  count  = var.cloud == "aws" ? 1 : 0

  subnetworks        = module.aws_network[0].subnetwork_ids
  security_group_ids = module.aws_security[0].security_group_ids
  workloads          = var.workloads
}
