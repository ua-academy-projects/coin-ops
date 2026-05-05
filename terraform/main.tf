locals {
  cfg      = try(jsondecode(file("${path.module}/config/config.json")), {})
  mapping  = try(jsondecode(file("${path.module}/config/mapping.json")), {})
  networks = try(jsondecode(file("${path.module}/config/networks.json")), {})
  gcp_cfg  = try(jsondecode(file("${path.module}/config/gcp.json")), {})
  aws_cfg  = try(jsondecode(file("${path.module}/config/aws.json")), {})

  instances      = lookup(local.cfg, "instances", {})
  general        = lookup(local.cfg, "general", {})
  subnets        = lookup(local.networks, "subnets", {})
  firewall_rules = lookup(local.networks, "firewall_rules", {})
  vpc_name       = lookup(local.networks, "vpc_name", "vpc-network")
  vpc_cidr       = lookup(local.networks, "vpc_cidr", "10.10.0.0/16")

  gcp_instance_sizes = try(local.mapping.instance_sizes.gcp, {})
  aws_instance_sizes = try(local.mapping.instance_sizes.aws, {})

  ssh_public_key = contains(var.enabled_clouds, "aws") && fileexists(var.ssh_public_key_path) ? file(var.ssh_public_key_path) : ""
}

# GCP

module "gcp_network" {
  count    = contains(var.enabled_clouds, "gcp") ? 1 : 0
  source   = "./modules/gcp_network"
  vpc_name = local.vpc_name
  region   = var.gcp_region
  subnets  = local.subnets
}

module "gcp_firewall" {
  count          = contains(var.enabled_clouds, "gcp") ? 1 : 0
  source         = "./modules/gcp_firewall"
  network_id     = module.gcp_network[0].network_id
  firewall_rules = local.firewall_rules
}

module "gcp_instances" {
  count          = contains(var.enabled_clouds, "gcp") ? 1 : 0
  source         = "./modules/gcp_instances"
  instances      = local.instances
  defaults       = local.general
  cloud_defaults = local.gcp_cfg
  instance_sizes = local.gcp_instance_sizes
  network_id     = module.gcp_network[0].network_id
  subnet_ids     = module.gcp_network[0].subnet_ids

  depends_on = [module.gcp_firewall]
}

# AWS

module "aws_network" {
  count    = contains(var.enabled_clouds, "aws") ? 1 : 0
  source   = "./modules/aws_network"
  vpc_name = local.vpc_name
  vpc_cidr = local.vpc_cidr
  subnets  = local.subnets
  zone     = lookup(local.aws_cfg, "zone", "${var.aws_region}a")
}

module "aws_security_groups" {
  count          = contains(var.enabled_clouds, "aws") ? 1 : 0
  source         = "./modules/aws_security_groups"
  vpc_id         = module.aws_network[0].vpc_id
  firewall_rules = local.firewall_rules
}

module "aws_instances" {
  count          = contains(var.enabled_clouds, "aws") ? 1 : 0
  source         = "./modules/aws_instances"
  instances      = local.instances
  defaults       = local.general
  cloud_defaults = local.aws_cfg
  instance_sizes = local.aws_instance_sizes
  subnet_ids     = module.aws_network[0].subnet_ids
  sg_ids         = module.aws_security_groups[0].sg_ids
  ssh_public_key = local.ssh_public_key
}
