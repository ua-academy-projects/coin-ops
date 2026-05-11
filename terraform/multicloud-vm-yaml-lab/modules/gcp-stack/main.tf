locals {
  stack          = var.stack
  domain_enabled = try(local.stack.domain.enabled, false)
  app_url        = local.domain_enabled ? "https://${local.stack.domain.name}" : "http://${module.certificate_dns.ip_address}"
  app_domain     = local.domain_enabled ? local.stack.domain.name : module.certificate_dns.ip_address

  bastion_target_tags = local.stack.instances[local.stack.bastion_name].tags
  app_target_tags     = distinct(flatten([for name in local.stack.app_names : local.stack.instances[name].tags]))
  db_target_tags      = local.stack.instances[local.stack.db_name].tags
  cloud_native        = try(local.stack.runtime.mode, "external") == "cloud_native"
  compute_instances   = local.cloud_native ? { for name, instance in local.stack.instances : name => instance if name != local.stack.db_name } : local.stack.instances
  runtime_base = merge(local.stack.runtime, {
    gcp_project_id = local.stack.gcp.project_id
  })
}

module "secrets" {
  source = "../shared/gcp-secrets"

  name_prefix = local.stack.name_prefix
  secrets     = local.stack.secrets
}
resource "google_service_account" "app" {
  count = local.cloud_native ? 1 : 0

  account_id   = "${replace(local.stack.name_prefix, "-", "")}-app"
  display_name = "${local.stack.name_prefix} app runtime"
}

module "queue" {
  count  = local.cloud_native ? 1 : 0
  source = "./modules/queue"

  name_prefix               = local.stack.name_prefix
  runtime                   = local.stack.runtime
  project_id                = local.stack.gcp.project_id
  app_service_account_email = google_service_account.app[0].email
}

module "database" {
  count  = local.cloud_native ? 1 : 0
  source = "./modules/database"

  name_prefix       = local.stack.name_prefix
  runtime           = local.stack.runtime
  project_id        = local.stack.gcp.project_id
  region            = local.stack.gcp.region
  network_self_link = module.network.network_self_link
  db_password       = var.db_password
}

module "cache" {
  count  = local.cloud_native ? 1 : 0
  source = "./modules/cache"

  name_prefix               = local.stack.name_prefix
  runtime                   = local.stack.runtime
  project_id                = local.stack.gcp.project_id
  region                    = local.stack.gcp.region
  network_self_link         = module.network.network_self_link
  private_subnet_self_links = module.network.private_subnet_self_links
}

module "network" {
  source = "./modules/network"

  name_prefix = local.stack.name_prefix
  network     = local.stack.network
  region      = local.stack.gcp.region
}

module "security" {
  source = "./modules/security"

  name_prefix             = local.stack.name_prefix
  network_self_link       = module.network.network_self_link
  firewall                = local.stack.firewall
  app_port                = local.stack.app.port
  bastion_target_tags     = local.bastion_target_tags
  app_target_tags         = local.app_target_tags
  db_target_tags          = local.db_target_tags
  allow_icmp_from_bastion = local.stack.firewall.allow_icmp_from_bastion
}

module "compute" {
  source = "./modules/compute"

  instances                 = local.compute_instances
  ssh                       = local.stack.ssh
  ssh_public_key            = local.stack.ssh_public_key
  zones                     = local.stack.gcp.zones
  app_names                 = local.stack.app_names
  db_name                   = local.stack.db_name
  bastion_name              = local.stack.bastion_name
  network_self_link         = module.network.network_self_link
  public_subnet_self_links  = module.network.public_subnet_self_links
  private_subnet_self_links = module.network.private_subnet_self_links
  app_service_account_email = local.cloud_native ? google_service_account.app[0].email : null
}

module "certificate_dns" {
  source = "./modules/certificate-dns"

  name_prefix = local.stack.name_prefix
  domain      = local.stack.domain
}

module "load_balancer" {
  source = "./modules/load-balancer"

  name_prefix           = local.stack.name_prefix
  app_instances         = module.compute.app_instances
  app_port              = local.stack.app.port
  health_path           = local.stack.app.health_path
  domain_enabled        = local.domain_enabled
  ip_address            = module.certificate_dns.ip_address
  certificate_self_link = module.certificate_dns.certificate_self_link
}

module "access_outputs" {
  source = "../shared/access-outputs"

  cloud       = "gcp"
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
  app_domain       = local.app_domain
  known_hosts_file = "~/.ssh/known_hosts_gcp_lab"
  secret_refs      = module.secrets.refs
  load_balancer    = module.load_balancer.load_balancer
}
