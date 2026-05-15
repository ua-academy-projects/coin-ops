data "google_secret_manager_secret_version" "db_secrets" {
  count   = local.gcp_enabled && !local.seed_secret_manager ? 1 : 0
  project = local.gcp_project_id
  secret  = "coinops-db-secrets"
  version = "latest"
}

data "google_secret_manager_secret_version" "app_secrets" {
  count   = local.gcp_enabled && !local.seed_secret_manager ? 1 : 0
  project = local.gcp_project_id
  secret  = "coinops-app-secrets"
  version = "latest"
}

module "gcp_network" {
  count    = local.gcp_enabled ? 1 : 0
  source   = "./modules/cloud/gcp/network"
  vpc_name = local.vpc_name
  region   = local.gcp_region
  subnets  = local.subnets
}

module "gcp_firewall" {
  count          = local.gcp_enabled ? 1 : 0
  source         = "./modules/cloud/gcp/firewall"
  network_id     = module.gcp_network[0].network_id
  firewall_rules = local.firewall_rules
}

module "gcp_instances" {
  count               = local.gcp_enabled ? 1 : 0
  source              = "./modules/cloud/gcp/instances"
  instances           = local.gcp_instances_cfg
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
  count            = local.gcp_enabled && local.gcp_has_nat_host ? 1 : 0
  source           = "./modules/cloud/gcp/nat_route"
  name             = local.nat_route_name
  network_id       = module.gcp_network[0].network_id
  destination_cidr = local.nat_destination_cidr
  priority         = local.nat_priority
  target_tags      = local.nat_target_tags
  next_hop_ip      = module.gcp_instances[0].instance_ips[local.gcp_nat_host_name].private_ip

  depends_on = [module.gcp_instances]
}

module "gcp_database" {
  count        = local.gcp_enabled ? 1 : 0
  source       = "./modules/cloud/gcp/database"
  project_name = local.project_name
  region       = local.gcp_region
  network_id   = module.gcp_network[0].network_id
  db_password  = local.effective_db_password
}

module "gcp_secrets" {
  count                = local.gcp_enabled ? 1 : 0
  source               = "./modules/cloud/gcp/secrets"
  db_password          = local.effective_db_password
  rabbitmq_password    = local.effective_rabbitmq_password
  ghcr_token           = local.effective_ghcr_token
  cloudflare_api_token = local.effective_cloudflare_api_token
}
