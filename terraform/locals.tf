locals {
  cfg = merge(
    try(jsondecode(file("${path.module}/config/clouds.json")), {}),
    try(jsondecode(file("${path.module}/config/general.json")), {}),
    try(jsondecode(file("${path.module}/config/deploy.json")), {}),
    try(jsondecode(file("${path.module}/config/dns.json")), {}),
    try(jsondecode(file("${path.module}/config/instances.json")), {})
  )
  mapping  = try(jsondecode(file("${path.module}/config/cloud_mappings.json")), {})
  networks = try(jsondecode(file("${path.module}/config/networks.json")), {})

  clouds          = lookup(local.cfg, "clouds", {})
  cloud_providers = lookup(local.clouds, "providers", {})
  gcp_provider    = lookup(local.cloud_providers, "gcp", {})
  aws_provider    = lookup(local.cloud_providers, "aws", {})
  gcp_account     = lookup(local.gcp_provider, "account", {})
  aws_account     = lookup(local.aws_provider, "account", {})
  deploy          = lookup(local.cfg, "deploy", {})
  dns             = lookup(local.cfg, "dns", {})
  general         = lookup(local.cfg, "general", {})

  enabled_clouds          = toset(try(local.clouds.enabled, ["gcp"]))
  control_plane_cloud     = try(local.clouds.control_plane, "gcp")
  default_instance_clouds = try(tolist(local.clouds.default_instance_clouds), tolist(local.enabled_clouds))

  instances = lookup(local.cfg, "instances", {})
  instance_clouds = {
    for name, cfg in local.instances : name => toset(try(tolist(lookup(cfg, "clouds", local.default_instance_clouds)), local.default_instance_clouds))
  }
  gcp_instances_base = {
    for name, cfg in local.instances : name => cfg
    if contains(local.instance_clouds[name], "gcp")
  }
  aws_instances_base = {
    for name, cfg in local.instances : name => cfg
    if contains(local.instance_clouds[name], "aws")
  }

  gcp_enabled = contains(local.enabled_clouds, "gcp") && length(local.gcp_instances_base) > 0
  aws_enabled = contains(local.enabled_clouds, "aws") && length(local.aws_instances_base) > 0

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

  ssh_public_key = fileexists(pathexpand(var.ssh_public_key_path)) ? file(pathexpand(var.ssh_public_key_path)) : ""

  seed_secret_manager = local.gcp_enabled && var.seed_secret_manager

  gcp_hosts = local.gcp_enabled ? try(module.gcp_instances[0].instance_ips, {}) : {}
  aws_hosts = local.aws_enabled ? try(module.aws_instances[0].instance_ips, {}) : {}

  gcp_jump_host_name = local.gcp_enabled ? try([
    for name, cfg in local.gcp_instances_base : name
    if lookup(cfg, "role", "") == "jump-host" && lookup(cfg, "has_public_ip", false)
  ][0], "") : ""
  gcp_nat_host_name = local.gcp_enabled ? try([
    for name, cfg in local.gcp_instances_base : name
    if lookup(cfg, "role", "") == "nat"
  ][0], "") : ""
  aws_jump_host_name = local.aws_enabled ? try([
    for name, cfg in local.aws_instances_base : name
    if lookup(cfg, "role", "") == "jump-host" && lookup(cfg, "has_public_ip", false)
  ][0], "") : ""
  aws_nat_host_name = local.aws_enabled ? try([
    for name, cfg in local.aws_instances_base : name
    if lookup(cfg, "role", "") == "nat"
  ][0], "") : ""

  gcp_has_nat_host = local.gcp_nat_host_name != ""
  aws_has_nat_host = local.aws_nat_host_name != ""

  nat_route_name       = try(local.private_default_route.name, "private-default-via-nat")
  nat_destination_cidr = try(local.private_default_route.destination_cidr, "0.0.0.0/0")
  nat_priority         = try(local.private_default_route.priority, 800)
  nat_target_tags      = try(local.private_default_route.target_tags, ["internal-vm"])
  private_subnet_cidr  = try(local.subnets["internal"].cidr, "10.10.1.0/24")

  username = trimspace(try(local.general.username, ""))
  ssh_port = try(local.general.ssh_port, 22)

  project_name   = try(local.general.project_name, "coin-ops")
  gcp_project_id = try(local.gcp_account.project_id, var.gcp_project_id)
  aws_account_id = try(local.aws_account.account_id, "")
  region_profile = try(local.general.region_profile, "europe-central")
  image_profile  = try(local.general.image_profile, "debian-12")
  aws_region     = try(local.aws_regions[local.region_profile].region, try(local.general.aws_region, var.aws_region))
  gcp_region     = try(local.gcp_regions[local.region_profile].region, try(local.general.gcp_region, var.gcp_region))
  gcp_zone       = try(local.gcp_regions[local.region_profile].zone, "${local.gcp_region}-a")
  aws_zone       = try(local.aws_regions[local.region_profile].zone, "${local.aws_region}a")

  app_domain         = try(local.deploy.app_domain, var.app_domain)
  cloudflare_config  = lookup(local.dns, "cloudflare", {})
  cloudflare_zone_id = try(local.cloudflare_config.zone_id, var.cloudflare_zone_id)

  gcp_cfg = {
    zone = local.gcp_zone
  }

  aws_cfg = {
    zone = local.aws_zone
  }

  gcp_instances_cfg = {
    for name, cfg in local.gcp_instances_base : name => merge(
      cfg,
      {
        os_image = (
          try(local.gcp_images[lookup(cfg, "image_profile", local.image_profile)].os_image, "") != ""
          ? local.gcp_images[lookup(cfg, "image_profile", local.image_profile)].os_image
          : (
            try(local.gcp_images[lookup(cfg, "image_profile", local.image_profile)].image_family, "") != ""
            ? "projects/${local.gcp_project_id}/global/images/family/${local.gcp_images[lookup(cfg, "image_profile", local.image_profile)].image_family}"
            : "debian-cloud/debian-12"
          )
        )
      }
    )
  }

  aws_instances_cfg = {
    for name, cfg in local.aws_instances_base : name => merge(
      cfg,
      {
        ami_filter = try(local.aws_images[lookup(cfg, "image_profile", local.image_profile)].ami_filter, "debian-12-amd64-*")
        ami_owner  = try(local.aws_images[lookup(cfg, "image_profile", local.image_profile)].ami_owner, "136693071363")
      }
    )
  }

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
