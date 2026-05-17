data "aws_secretsmanager_secret_version" "db_secrets" {
  count     = local.read_aws_secret_backend ? 1 : 0
  secret_id = local.db_secret_name
}

data "aws_secretsmanager_secret_version" "app_secrets" {
  count     = local.read_aws_secret_backend ? 1 : 0
  secret_id = local.app_secret_name
}

module "aws_network" {
  count    = local.aws_enabled ? 1 : 0
  source   = "./modules/cloud/aws/network"
  vpc_name = local.vpc_name
  vpc_cidr = local.vpc_cidr
  subnets  = local.subnets
  zone     = lookup(local.aws_cfg, "zone", "${local.aws_region}a")
  zones    = lookup(local.aws_cfg, "zones", {})
}

module "aws_security_groups" {
  count          = local.aws_enabled ? 1 : 0
  source         = "./modules/cloud/aws/security_groups"
  vpc_id         = module.aws_network[0].vpc_id
  firewall_rules = local.firewall_rules
  egress_cidrs   = local.egress_cidrs
}

module "aws_instances" {
  count               = local.aws_compute_enabled ? 1 : 0
  source              = "./modules/cloud/aws/instances"
  instances           = local.aws_instances_cfg
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
  count                    = local.aws_compute_enabled && local.aws_has_nat_host ? 1 : 0
  source                   = "./modules/cloud/aws/nat_route"
  private_route_table_id   = module.aws_network[0].private_route_table_id
  nat_network_interface_id = module.aws_instances[0].instance_primary_network_interface_ids[local.aws_nat_host_name]
  destination_cidr         = local.nat_destination_cidr

  depends_on = [module.aws_instances]
}

module "aws_database" {
  count                     = local.aws_enabled && local.database_enabled ? 1 : 0
  source                    = "./modules/cloud/aws/database"
  project_name              = local.project_name
  vpc_id                    = module.aws_network[0].vpc_id
  subnet_ids                = module.aws_network[0].database_subnet_ids
  backend_security_group_id = module.aws_security_groups[0].sg_ids["app-backend"]
  db_password               = local.effective_db_password
  db_name                   = local.db_name
  db_username               = local.db_username
  db_port                   = local.db_port
  engine_version            = try(local.database.version, "16")
  instance_class            = try(local.aws_db_profile.instance_class, "db.t4g.micro")
  allocated_storage         = try(local.aws_db_profile.allocated_storage, 20)
  storage_type              = try(local.aws_db_profile.storage_type, "gp3")
  backup_retention_period   = try(local.aws_db_profile.backup_retention_period, 7)
  multi_az                  = try(local.aws_db_profile.multi_az, false)
}

module "aws_secrets" {
  count                = local.write_aws_secret_backend ? 1 : 0
  source               = "./modules/cloud/aws/secrets"
  db_secret_name       = local.db_secret_name
  app_secret_name      = local.app_secret_name
  db_password          = local.effective_db_password
  rabbitmq_password    = local.effective_rabbitmq_password
  ghcr_token           = local.effective_ghcr_token
  cloudflare_api_token = local.effective_cloudflare_api_token
}
