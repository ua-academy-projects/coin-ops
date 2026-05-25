module "db" {
  source = "./modules/DB"

  cloud_provider       = var.cloud_provider
  db_instance_class    = local.db_instance_class
  db_engine_version    = local.db_config.db_engine_version
  db_allocated_storage = local.db_config.db_allocated_storage
  db_storage_type      = local.db_storage_type
  db_name              = local.db_config.db_name
  db_username          = local.db_config.db_username

  backup_retention_days = local.db_config.backup_retention_days
  multi_az              = local.db_config.multi_az
  deletion_protection   = local.db_config.deletion_protection

  vpc_id              = module.networking.vpc_id
  subnet_ids          = values(module.networking.subnet_ids)
  security_group_ids  = local.is_aws ? [module.networking.security_group_ids["db"]] : []
  gcp_project_id      = var.gcp_project_id
  region              = local.region
  common_tags         = local.common_tags
  resource_group_name = module.networking.resource_group_name
}

module "secrets" {
  source = "./modules/secrets"

  cloud_provider      = var.cloud_provider
  region              = local.region
  gcp_project_id      = var.gcp_project_id
  common_tags         = local.common_tags
  resource_group_name = module.networking.resource_group_name

  db_username       = local.db_config.db_username
  db_name           = local.db_config.db_name
  db_password       = module.db.db_password
  db_host           = module.db.db_instance_address
  rabbitmq_password = var.rabbitmq_password
}

module "networking" {
  source = "./modules/networking"

  cloud_provider = var.cloud_provider

  vpc_name       = local.networking_config.vpc_name
  vpc_cidr       = local.networking_config.vpc_cidr
  region_map     = local.mappings.region_map
  region         = local.networking_config.region
  subnets        = local.networking_config.subnets
  firewall_rules = local.networking_config.firewall_rules
  common_tags    = local.common_tags
}

module "compute" {
  source = "./modules/compute"

  cloud_provider    = var.cloud_provider
  instance_type_map = local.mappings.instance_type_map
  image_map         = local.mappings.image_map
  disk_type_map     = local.mappings.disk_type_map
  zone_map          = local.mappings.zone_map
  vms               = local.compute_config.vms

  vpc_id             = module.networking.vpc_id
  subnet_ids         = module.networking.subnet_ids
  security_group_ids = local.is_aws ? values(module.networking.security_group_ids) : []

  ssh_user            = var.ssh_user
  ssh_public_key      = local.ssh_public_key_content
  gcp_project_id      = var.gcp_project_id
  common_tags         = local.common_tags
  resource_group_name = module.networking.resource_group_name
  region              = local.region
  use_packer_image    = var.use_packer_image
}

module "load_balancer" {
  source = "./modules/load_balancer"

  cloud_provider      = var.cloud_provider
  name                = local.lb_config.name
  region              = local.region
  vpc_id              = module.networking.vpc_id
  vpc_cidr            = local.networking_config.vpc_cidr
  subnet_ids          = module.networking.subnet_ids
  gcp_project_id      = var.gcp_project_id
  common_tags         = local.common_tags
  resource_group_name = module.networking.resource_group_name

  backends = {
    for name, b in local.lb_config.backends : name => {
      subnet_name = b.subnet_name
      port        = b.port
      zone        = local.mappings.zone_map[local.compute_config.vms[name].zone][var.cloud_provider]
    }
  }

  health_check = local.lb_config.health_check
  listeners    = local.lb_config.listeners
  domains      = try(local.lb_config.domains, [])

  instance_ids        = module.compute.instance_ids
  instance_self_links = module.compute.instance_self_links
  ip_address          = try(local.lb_config.ip_address, null)
}
