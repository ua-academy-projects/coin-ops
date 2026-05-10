locals {
  cfg      = try(jsondecode(file("${path.module}/config/config.json")), {})
  mapping  = try(jsondecode(file("${path.module}/config/cloud_mappings.json")), {})
  networks = try(jsondecode(file("${path.module}/config/networks.json")), {})

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
  gcp_regions        = try(local.mapping.regions.gcp, {})
  aws_regions        = try(local.mapping.regions.aws, {})
  gcp_images         = try(local.mapping.images.gcp, {})
  aws_images         = try(local.mapping.images.aws, {})

  # Shared SSH key — used for both GCP metadata and AWS key pair.
  # pathexpand() is required so "~/.ssh/..." works on local machines.
  ssh_public_key = fileexists(pathexpand(var.ssh_public_key_path)) ? file(pathexpand(var.ssh_public_key_path)) : ""

  # Enabled clouds ("gcp", "aws")
  gcp_enabled         = contains(var.enabled_clouds, "gcp")
  aws_enabled         = contains(var.enabled_clouds, "aws")
  seed_secret_manager = local.gcp_enabled && var.seed_secret_manager

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
  username = trimspace(try(local.general.username, ""))
  ssh_port = try(local.general.ssh_port, 22)

  # Project and regions from config.json
  project_name = try(local.general.project_name, "coin-ops")
  region_profile = try(local.general.region_profile, "europe-central")
  image_profile  = try(local.general.image_profile, "debian-12")
  aws_region     = try(local.aws_regions[local.region_profile].region, try(local.general.aws_region, var.aws_region))
  gcp_region     = try(local.gcp_regions[local.region_profile].region, try(local.general.gcp_region, var.gcp_region))
  gcp_zone       = try(local.gcp_regions[local.region_profile].zone, "${local.gcp_region}-a")
  aws_zone       = try(local.aws_regions[local.region_profile].zone, "${local.aws_region}a")

  gcp_cfg = merge(
    {
      zone     = local.gcp_zone
      os_image = try(local.gcp_images[local.image_profile].os_image, "debian-cloud/debian-12")
    },
    try(local.cfg.cloud_defaults.gcp, {})
  )

  aws_cfg = merge(
    {
      zone       = local.aws_zone
      ami_filter = try(local.aws_images[local.image_profile].ami_filter, "debian-12-amd64-*")
      ami_owner  = try(local.aws_images[local.image_profile].ami_owner, "136693071363")
    },
    try(local.cfg.cloud_defaults.aws, {})
  )

  gcp_db_secrets  = local.gcp_enabled && !local.seed_secret_manager ? try(jsondecode(data.google_secret_manager_secret_version.db_secrets[0].secret_data), {}) : {}
  gcp_app_secrets = local.gcp_enabled && !local.seed_secret_manager ? try(jsondecode(data.google_secret_manager_secret_version.app_secrets[0].secret_data), {}) : {}

  effective_db_password = local.gcp_enabled ? (
    local.seed_secret_manager ? var.db_password : try(local.gcp_db_secrets.DB_PASSWORD, "")
  ) : var.db_password
  effective_rabbitmq_password = local.gcp_enabled ? (
    local.seed_secret_manager ? var.rabbitmq_password : try(local.gcp_db_secrets.RABBITMQ_PASSWORD, "")
  ) : var.rabbitmq_password
  effective_ghcr_token = local.gcp_enabled ? (
    local.seed_secret_manager ? var.ghcr_token : try(local.gcp_app_secrets.GHCR_TOKEN, "")
  ) : var.ghcr_token
  effective_cloudflare_api_token = local.gcp_enabled ? (
    local.seed_secret_manager ? var.cloudflare_api_token : try(local.gcp_app_secrets.CLOUDFLARE_API_TOKEN, "")
  ) : var.cloudflare_api_token
}

data "google_secret_manager_secret_version" "db_secrets" {
  count   = local.gcp_enabled && !local.seed_secret_manager ? 1 : 0
  project = var.gcp_project_id
  secret  = "coinops-db-secrets"
  version = "latest"
}

data "google_secret_manager_secret_version" "app_secrets" {
  count   = local.gcp_enabled && !local.seed_secret_manager ? 1 : 0
  project = var.gcp_project_id
  secret  = "coinops-app-secrets"
  version = "latest"
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
  db_password  = local.effective_db_password
}

module "gcp_secrets" {
  count                = local.gcp_enabled ? 1 : 0
  source               = "./modules/gcp_secrets"
  db_password          = local.effective_db_password
  rabbitmq_password    = local.effective_rabbitmq_password
  ghcr_token           = local.effective_ghcr_token
  cloudflare_api_token = local.effective_cloudflare_api_token
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
# Written after every apply for operator/debugging use only.
# Ansible no longer depends on this artifact for runtime host selection.

resource "local_file" "hosts" {
  filename = "${path.module}/config/hosts.json"
  content = jsonencode(merge(
    local.gcp_enabled ? {
      gcp = {
        ssh_user    = local.username
        ssh_port    = local.ssh_port
        instances   = try(module.gcp_instances[0].instance_ips, {})
        database_ip = try(module.gcp_database[0].private_ip, "")
      }
    } : {},
    local.aws_enabled ? {
      aws = {
        ssh_user  = local.username
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
          User ${local.username}
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
          User ${local.username}
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

resource "local_file" "ansible_runtime" {
  filename = "${path.module}/config/ansible-runtime.json"
  content = jsonencode(merge(
    local.gcp_enabled ? {
      gcp = {
        database_ip        = try(module.gcp_database[0].private_ip, "")
        use_managed_db     = try(module.gcp_database[0].private_ip, "") != ""
      }
    } : {},
    local.aws_enabled ? {
      aws = {
        database_ip        = ""
        use_managed_db     = false
      }
    } : {}
  ))
}

# Sync SSH config to global ~/.ssh/extra_configs for convenience (WSL/Linux only).
# This ensures permissions are correct (600) so SSH doesn't complain about world-writable files on /mnt/d.
resource "null_resource" "sync_ssh_config" {
  triggers = {
    config_content = local_file.ssh_config.content
  }

  provisioner "local-exec" {
    command = <<EOT
      mkdir -p ~/.ssh/extra_configs
      cp ${local_file.ssh_config.filename} ~/.ssh/extra_configs/coin-ops-ssh-config
      chmod 600 ~/.ssh/extra_configs/coin-ops-ssh-config
    EOT
  }
}
