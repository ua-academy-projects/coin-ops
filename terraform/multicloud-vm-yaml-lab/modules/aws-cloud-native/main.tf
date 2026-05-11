locals {
  stack          = var.stack
  domain_enabled = try(local.stack.domain.enabled, false)
  app_url        = local.domain_enabled ? "https://${local.stack.domain.name}" : "http://${module.load_balancer.dns_name}"
  cloud_native   = try(local.stack.runtime.mode, "external") == "cloud_native"
  runtime_base = merge(local.stack.runtime, {
    aws_region  = local.stack.aws.region
    aws_profile = try(local.stack.aws.profile, "")
  })
}

module "secrets" {
  source = "../shared/aws-secrets"

  name_prefix = local.stack.name_prefix
  secrets     = local.stack.secrets
}
module "queue" {
  count  = local.cloud_native ? 1 : 0
  source = "./modules/queue"

  name_prefix               = local.stack.name_prefix
  runtime                   = local.stack.runtime
  app_instance_profile_name = local.stack.aws.app_instance_profile_name
}

module "database" {
  count  = local.cloud_native ? 1 : 0
  source = "./modules/database"

  name_prefix           = local.stack.name_prefix
  runtime               = local.stack.runtime
  vpc_id                = module.network.vpc_id
  private_subnet_ids    = module.network.private_subnet_ids
  app_security_group_id = module.security.security_group_ids.app
  db_password           = var.db_password
}

module "cache" {
  count  = local.cloud_native ? 1 : 0
  source = "./modules/cache"

  name_prefix           = local.stack.name_prefix
  runtime               = local.stack.runtime
  vpc_id                = module.network.vpc_id
  private_subnet_ids    = module.network.private_subnet_ids
  app_security_group_id = module.security.security_group_ids.app
}

module "network" {
  source = "./modules/network"

  name_prefix     = local.stack.name_prefix
  network         = local.stack.network
  public_subnets  = local.stack.network.public_subnets
  private_subnets = local.stack.network.private_subnets
}

module "security" {
  source = "./modules/security"

  name_prefix = local.stack.name_prefix
  vpc_id      = module.network.vpc_id
  firewall    = local.stack.firewall
  app_port    = local.stack.app.port
}

module "compute" {
  source = "./modules/compute"

  name_prefix                   = local.stack.name_prefix
  instances                     = local.stack.instances
  image_catalog                 = local.stack.image_catalog
  ssh                           = local.stack.ssh
  ssh_public_key                = local.stack.ssh_public_key
  app_names                     = local.stack.app_names
  db_name                       = local.stack.db_name
  bastion_name                  = local.stack.bastion_name
  public_subnet_ids             = module.network.public_subnet_ids
  private_subnet_ids            = module.network.private_subnet_ids
  security_groups               = module.security.security_group_ids
  create_db_instance            = !local.cloud_native
  app_iam_instance_profile_name = local.cloud_native ? module.queue[0].app_instance_profile_name : null
}

module "load_balancer" {
  source = "./modules/load-balancer"

  name_prefix          = local.stack.name_prefix
  vpc_id               = module.network.vpc_id
  public_subnet_ids    = module.network.public_subnet_ids
  lb_security_group_id = module.security.security_group_ids.lb
  app_instance_ids     = { for name in local.stack.app_names : name => module.compute.app_instances[name].id }
  app_port             = local.stack.app.port
  health_path          = local.stack.app.health_path
}

module "certificate_dns" {
  source = "./modules/certificate-dns"

  name_prefix      = local.stack.name_prefix
  domain           = local.stack.domain
  lb_arn           = module.load_balancer.arn
  lb_dns_name      = module.load_balancer.dns_name
  target_group_arn = module.load_balancer.target_group_arn
}

module "access_outputs" {
  source = "../shared/access-outputs"

  cloud       = "aws"
  name_prefix = local.stack.name_prefix
  ssh         = local.stack.ssh
  instances   = module.compute.instances
  runtime = local.cloud_native ? merge(local.runtime_base, {
    database = merge(local.stack.runtime.database, module.database[0].database)
    queue    = merge(local.stack.runtime.queue, module.queue[0].queue)
    cache    = merge(local.stack.runtime.cache, module.cache[0].cache)
    }) : merge(local.runtime_base, {
    database = merge(local.stack.runtime.database, {
      managed = false
      host    = module.compute.instances[local.stack.db_name].private_ip
      port    = 5432
      name    = local.stack.runtime.database.name
      user    = local.stack.runtime.database.user
    })
    queue = merge(local.stack.runtime.queue, {
      backend      = local.stack.runtime.mode == "postgres" ? "postgres" : "rabbitmq"
      url          = ""
      topic        = ""
      subscription = ""
    })
    cache = merge(local.stack.runtime.cache, {
      managed   = false
      backend   = "redis"
      host      = module.compute.instances[local.stack.db_name].private_ip
      port      = 6379
      redis_url = "redis://${module.compute.instances[local.stack.db_name].private_ip}:6379/0"
    })
  })
  bastion_name     = local.stack.bastion_name
  app_names        = local.stack.app_names
  db_name          = local.stack.db_name
  app_url          = local.app_url
  app_domain       = local.domain_enabled ? local.stack.domain.name : module.load_balancer.dns_name
  known_hosts_file = "~/.ssh/known_hosts_aws_lab"
  secret_refs      = module.secrets.refs
  load_balancer = {
    dns_name         = module.load_balancer.dns_name
    zone_id          = module.load_balancer.zone_id
    https_enabled    = local.domain_enabled
    target_group_arn = module.load_balancer.target_group_arn
  }
}
