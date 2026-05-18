data "google_secret_manager_secret_version" "db_secrets" {
  count   = local.read_gcp_secret_backend ? 1 : 0
  project = local.gcp_project_id
  secret  = local.db_secret_name
  version = "latest"
}

data "google_secret_manager_secret_version" "app_secrets" {
  count   = local.read_gcp_secret_backend ? 1 : 0
  project = local.gcp_project_id
  secret  = local.app_secret_name
  version = "latest"
}

module "gcp_network" {
  count    = local.gcp_enabled ? 1 : 0
  source   = "./modules/cloud/gcp/network"
  vpc_name = local.gcp_vpc_name
  region   = local.gcp_region
  subnets  = local.gcp_subnets
}

module "gcp_firewall" {
  count          = local.gcp_enabled ? 1 : 0
  source         = "./modules/cloud/gcp/firewall"
  network_id     = module.gcp_network[0].network_id
  firewall_rules = local.firewall_rules
}

module "gcp_instances" {
  count               = local.gcp_compute_enabled ? 1 : 0
  source              = "./modules/cloud/gcp/instances"
  instances           = local.gcp_instances_cfg
  defaults            = local.general
  cloud_defaults      = local.gcp_cfg
  instance_sizes      = local.gcp_instance_sizes
  network_id          = module.gcp_network[0].network_id
  subnet_ids          = module.gcp_network[0].subnet_ids
  ssh_public_key      = local.ssh_public_key
  private_subnet_cidr = local.gcp_private_subnet_cidr
  vpc_cidr            = local.gcp_vpc_cidr
  username            = local.username
  ssh_port            = local.ssh_port
  project_name        = local.project_name

  depends_on = [module.gcp_firewall]
}

module "gcp_nat_route" {
  count       = local.gcp_compute_enabled && local.gcp_has_route_host ? 1 : 0
  source      = "./modules/cloud/gcp/nat_route"
  network_id  = module.gcp_network[0].network_id
  routes      = local.gcp_route_specs
  next_hop_ip = try(module.gcp_instances[0].instance_ips[local.gcp_route_host_name].private_ip, "")

  depends_on = [module.gcp_instances]
}

module "gcp_database" {
  count        = local.gcp_enabled && local.database_enabled ? 1 : 0
  source       = "./modules/cloud/gcp/database"
  project_name = local.project_name
  region       = local.gcp_region
  network_id   = module.gcp_network[0].network_id
  db_password  = local.effective_db_password
  db_name      = local.db_name
  db_username  = local.db_username
  db_tier      = try(local.gcp_db_profile.tier, "db-f1-micro")
  disk_type    = try(local.gcp_db_profile.disk_type, "PD_HDD")
  disk_size    = try(local.gcp_db_profile.disk_size, 10)
}

module "gcp_secrets" {
  count                = local.write_gcp_secret_backend ? 1 : 0
  source               = "./modules/cloud/gcp/secrets"
  db_secret_name       = local.db_secret_name
  app_secret_name      = local.app_secret_name
  db_password          = local.effective_db_password
  rabbitmq_password    = local.effective_rabbitmq_password
  ghcr_token           = local.effective_ghcr_token
  cloudflare_api_token = local.effective_cloudflare_api_token
  tailscale_auth_key   = local.effective_tailscale_auth_key
}
