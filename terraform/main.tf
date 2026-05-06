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

  # Shared SSH key — used for both GCP metadata and AWS key pair.
  # pathexpand() is required so "~/.ssh/..." works on local machines.
  ssh_public_key = fileexists(pathexpand(var.ssh_public_key_path)) ? file(pathexpand(var.ssh_public_key_path)) : ""

  # Enabled clouds ("gcp", "aws")
  gcp_enabled = contains(var.enabled_clouds, "gcp")
  aws_enabled = contains(var.enabled_clouds, "aws")
}

# GCP

module "gcp_network" {
  count    = local.gcp_enabled ? 1 : 0
  source   = "./modules/gcp_network"
  vpc_name = local.vpc_name
  region   = var.gcp_region
  subnets  = local.subnets
}

module "gcp_firewall" {
  count          = local.gcp_enabled ? 1 : 0
  source         = "./modules/gcp_firewall"
  network_id     = module.gcp_network[0].network_id
  firewall_rules = local.firewall_rules
}

module "gcp_instances" {
  count          = local.gcp_enabled ? 1 : 0
  source         = "./modules/gcp_instances"
  instances      = local.instances
  defaults       = local.general
  cloud_defaults = local.gcp_cfg
  instance_sizes = local.gcp_instance_sizes
  network_id     = module.gcp_network[0].network_id
  subnet_ids     = module.gcp_network[0].subnet_ids
  ssh_public_key = local.ssh_public_key

  depends_on = [module.gcp_firewall]
}

# Route for internal VMs (tagged "internal-vm") to reach the internet via jump-host NAT.
# Priority 800 overrides the default internet-gateway route (priority 1000) for these VMs.
# next_hop_ip uses the jump-host private IP — always a concrete value or (known after apply),
# never null, which avoids the "one of next_hop_* must be specified" provider error.
resource "google_compute_route" "nat_route" {
  count       = local.gcp_enabled ? 1 : 0
  name        = "coin-ops-nat-route"
  network     = module.gcp_network[0].network_id
  dest_range  = "0.0.0.0/0"
  priority    = 800
  tags        = ["internal-vm"]
  next_hop_ip = module.gcp_instances[0].instance_ips["jump-host"].private_ip

  depends_on = [module.gcp_instances]
}

# AWS

module "aws_network" {
  count    = local.aws_enabled ? 1 : 0
  source   = "./modules/aws_network"
  vpc_name = local.vpc_name
  vpc_cidr = local.vpc_cidr
  subnets  = local.subnets
  zone     = lookup(local.aws_cfg, "zone", "${var.aws_region}a")
}

module "aws_security_groups" {
  count          = local.aws_enabled ? 1 : 0
  source         = "./modules/aws_security_groups"
  vpc_id         = module.aws_network[0].vpc_id
  firewall_rules = local.firewall_rules
}

module "aws_instances" {
  count          = local.aws_enabled ? 1 : 0
  source         = "./modules/aws_instances"
  instances      = local.instances
  defaults       = local.general
  cloud_defaults = local.aws_cfg
  instance_sizes = local.aws_instance_sizes
  subnet_ids     = module.aws_network[0].subnet_ids
  sg_ids         = module.aws_security_groups[0].sg_ids
  ssh_public_key = local.ssh_public_key
}

# hosts.json
# Written after every apply. Used by the Ansible dynamic inventory script.
# Add config/hosts.json to .gitignore — it contains live infrastructure IPs.

resource "local_file" "hosts" {
  filename = "${path.module}/config/hosts.json"
  content = jsonencode(merge(
    local.gcp_enabled ? {
      gcp = {
        ssh_user  = lookup(local.gcp_cfg, "ssh_user", "debian")
        instances = try(module.gcp_instances[0].instance_ips, {})
      }
    } : {},
    local.aws_enabled ? {
      aws = {
        ssh_user  = lookup(local.aws_cfg, "ssh_user", "ec2-user")
        instances = try(module.aws_instances[0].instance_ips, {})
      }
    } : {}
  ))
}
