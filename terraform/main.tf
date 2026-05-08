locals {
  cfg      = try(jsondecode(file("${path.module}/config/config.json")), {})
  mapping  = try(jsondecode(file("${path.module}/config/mapping.json")), {})
  networks = try(jsondecode(file("${path.module}/config/networks.json")), {})
  gcp_cfg  = try(jsondecode(file("${path.module}/config/gcp.json")), {})
  aws_cfg  = try(jsondecode(file("${path.module}/config/aws.json")), {})

  instances             = lookup(local.cfg, "instances", {})
  general               = lookup(local.cfg, "general", {})
  subnets               = lookup(local.networks, "subnets", {})
  firewall_rules        = lookup(local.networks, "firewall_rules", {})
  routing               = lookup(local.networks, "routing", {})
  security              = lookup(local.networks, "security", {})
  vpc_name              = lookup(local.networks, "vpc_name", "vpc-network")
  vpc_cidr              = lookup(local.networks, "vpc_cidr", "10.10.0.0/16")
  private_default_route = lookup(local.routing, "private_default_route", {})
  egress_cidrs          = lookup(local.security, "egress_cidrs", ["0.0.0.0/0"])

  gcp_instance_sizes = try(local.mapping.instance_sizes.gcp, {})
  aws_instance_sizes = try(local.mapping.instance_sizes.aws, {})

  # Shared SSH key — used for both GCP metadata and AWS key pair.
  # pathexpand() is required so "~/.ssh/..." works on local machines.
  ssh_public_key = fileexists(pathexpand(var.ssh_public_key_path)) ? file(pathexpand(var.ssh_public_key_path)) : ""

  # Enabled clouds ("gcp", "aws")
  gcp_enabled = contains(var.enabled_clouds, "gcp")
  aws_enabled = contains(var.enabled_clouds, "aws")

  # Derived from resource outputs — used only in ssh_config/hosts.json (apply-time, valid there).
  gcp_hosts = local.gcp_enabled ? try(module.gcp_instances[0].instance_ips, {}) : {}
  aws_hosts = local.aws_enabled ? try(module.aws_instances[0].instance_ips, {}) : {}

  # Derived from config input — plan-time safe, used in count and next_hop_ip key lookup.
  # count must not depend on resource attributes; instance names are known from config.json.
  gcp_jump_host_name = local.gcp_enabled ? try([
    for name, cfg in local.instances : name
    if lookup(cfg, "role", "") == "jump-host" && lookup(cfg, "has_public_ip", false)
  ][0], "") : ""
  aws_jump_host_name = local.aws_enabled ? try([
    for name, cfg in local.instances : name
    if lookup(cfg, "role", "") == "jump-host" && lookup(cfg, "has_public_ip", false)
  ][0], "") : ""

  # Guards: NAT route modules are only created when a jump-host is present in config.
  gcp_has_jump_host = local.gcp_jump_host_name != ""
  aws_has_jump_host = local.aws_jump_host_name != ""

  # NAT route params with fallback values so apply succeeds even without networks.json.
  nat_route_name       = try(local.private_default_route.name, "private-default-via-jump")
  nat_destination_cidr = try(local.private_default_route.destination_cidr, "0.0.0.0/0")
  nat_priority         = try(local.private_default_route.priority, 800)
  nat_target_tags      = try(local.private_default_route.target_tags, ["internal-vm"])

  # CIDR of the private subnet — injected into startup script templates.
  # Derived from networks.json; fallback matches the hardcoded default in the script.
  private_subnet_cidr = try(local.subnets["internal"].cidr, "10.10.1.0/24")

  # Custom OS user and SSH port — from config.json → general.
  # Injected into user_init_script template; also used in generated ssh_config.
  username = try(local.general.username, "")
  ssh_port = try(local.general.ssh_port, 22)

  # Project and regions from config.json
  project_name = try(local.general.project_name, "coin-ops")
  aws_region   = try(local.general.aws_region, var.aws_region)
  gcp_region   = try(local.general.gcp_region, var.gcp_region)
}

# GCP

module "gcp_network" {
  count    = local.gcp_enabled ? 1 : 0
  source   = "./modules/gcp_network"
  vpc_name = local.vpc_name
  region   = local.gcp_region
  subnets  = local.subnets
}

module "gcp_firewall" {
  count          = local.gcp_enabled ? 1 : 0
  source         = "./modules/gcp_firewall"
  network_id     = module.gcp_network[0].network_id
  firewall_rules = local.firewall_rules
}

module "gcp_instances" {
  count               = local.gcp_enabled ? 1 : 0
  source              = "./modules/gcp_instances"
  instances           = local.instances
  defaults            = local.general
  cloud_defaults      = local.gcp_cfg
  instance_sizes      = local.gcp_instance_sizes
  network_id          = module.gcp_network[0].network_id
  subnet_ids          = module.gcp_network[0].subnet_ids
  ssh_public_key      = local.ssh_public_key
  private_subnet_cidr = local.private_subnet_cidr
  username            = local.username
  ssh_port            = local.ssh_port
  project_name        = local.project_name

  depends_on = [module.gcp_firewall]
}

module "gcp_nat_route" {
  count            = local.gcp_enabled && local.gcp_has_jump_host ? 1 : 0
  source           = "./modules/gcp_nat_route"
  name             = local.nat_route_name
  network_id       = module.gcp_network[0].network_id
  destination_cidr = local.nat_destination_cidr
  priority         = local.nat_priority
  target_tags      = local.nat_target_tags
  next_hop_ip      = module.gcp_instances[0].instance_ips[local.gcp_jump_host_name].private_ip

  depends_on = [module.gcp_instances]
}

module "gcp_database" {
  count        = local.gcp_enabled ? 1 : 0
  source       = "./modules/gcp_database"
  project_name = local.project_name
  region       = local.gcp_region
  network_id   = module.gcp_network[0].network_id
  db_password  = var.db_password
}

# AWS

module "aws_network" {
  count    = local.aws_enabled ? 1 : 0
  source   = "./modules/aws_network"
  vpc_name = local.vpc_name
  vpc_cidr = local.vpc_cidr
  subnets  = local.subnets
  zone     = lookup(local.aws_cfg, "zone", "${local.aws_region}a")
}

module "aws_security_groups" {
  count          = local.aws_enabled ? 1 : 0
  source         = "./modules/aws_security_groups"
  vpc_id         = module.aws_network[0].vpc_id
  firewall_rules = local.firewall_rules
  egress_cidrs   = local.egress_cidrs
}

module "aws_instances" {
  count               = local.aws_enabled ? 1 : 0
  source              = "./modules/aws_instances"
  instances           = local.instances
  defaults            = local.general
  cloud_defaults      = local.aws_cfg
  instance_sizes      = local.aws_instance_sizes
  subnet_ids          = module.aws_network[0].subnet_ids
  sg_ids              = module.aws_security_groups[0].sg_ids
  ssh_public_key      = local.ssh_public_key
  private_subnet_cidr = local.private_subnet_cidr
  username            = local.username
  ssh_port            = local.ssh_port
  project_name        = local.project_name
}

module "aws_nat_route" {
  count                    = local.aws_enabled && local.aws_has_jump_host ? 1 : 0
  source                   = "./modules/aws_nat_route"
  private_route_table_id   = module.aws_network[0].private_route_table_id
  nat_network_interface_id = module.aws_instances[0].instance_primary_network_interface_ids[local.aws_jump_host_name]
  destination_cidr         = local.nat_destination_cidr

  depends_on = [module.aws_instances]
}

# hosts.json
# Written after every apply. Used by the Ansible dynamic inventory script.
# Add config/hosts.json to .gitignore — it contains live infrastructure IPs.

resource "local_file" "hosts" {
  filename = "${path.module}/config/hosts.json"
  content = jsonencode(merge(
    local.gcp_enabled ? {
      gcp = {
        ssh_user  = local.username != "" ? local.username : lookup(local.gcp_cfg, "ssh_user", "debian")
        ssh_port  = local.ssh_port
        instances = try(module.gcp_instances[0].instance_ips, {})
      }
    } : {},
    local.aws_enabled ? {
      aws = {
        ssh_user  = local.username != "" ? local.username : lookup(local.aws_cfg, "ssh_user", "ec2-user")
        ssh_port  = local.ssh_port
        instances = try(module.aws_instances[0].instance_ips, {})
      }
    } : {}
  ))
}

# Generated SSH config with current Terraform IPs.
# Usage:
#   ssh -F config/ssh_config coinops-app2
#   ssh -F config/ssh_config coinops-db1
resource "local_file" "ssh_config" {
  filename = "${path.module}/config/ssh_config"
  content = trimspace(join("\n\n", concat(
    local.gcp_enabled ? [
      for name, inst in local.gcp_hosts : trimspace(<<-EOT
        Host coinops-gcp-${name}
          HostName ${inst.role == "jump-host" ? inst.public_ip : inst.private_ip}
          User ${local.username != "" ? local.username : lookup(local.gcp_cfg, "ssh_user", "debian")}
          Port ${local.ssh_port}
          ${inst.role != "jump-host" && local.gcp_jump_host_name != "" ? "ProxyJump coinops-gcp-${local.gcp_jump_host_name}" : ""}
          IdentityFile ${pathexpand(replace(var.ssh_public_key_path, ".pub", ""))}
          IdentitiesOnly yes
          StrictHostKeyChecking no
          UserKnownHostsFile /dev/null
      EOT
      )
    ] : [],
    local.aws_enabled ? [
      for name, inst in local.aws_hosts : trimspace(<<-EOT
        Host coinops-aws-${name}
          HostName ${inst.public_ip != null ? inst.public_ip : inst.private_ip}
          User ${local.username != "" ? local.username : lookup(local.aws_cfg, "ssh_user", "ec2-user")}
          Port ${local.ssh_port}
          ${inst.public_ip == null && local.aws_jump_host_name != "" ? "ProxyJump coinops-aws-${local.aws_jump_host_name}" : ""}
          IdentityFile ${pathexpand(replace(var.ssh_public_key_path, ".pub", ""))}
          IdentitiesOnly yes
          StrictHostKeyChecking no
          UserKnownHostsFile /dev/null
      EOT
      )
    ] : []
  )))
}
