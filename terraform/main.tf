locals {
  raw_config = yamldecode(file("${path.module}/../config.yaml"))

  config = merge(local.raw_config, {
    general = merge(local.raw_config.general, {
      db_password = var.db_password
    })
  })

  general  = local.config.general
  cloud    = local.general.cloud
  location = local.general.location

  active_location = local.cloud == "hybrid" ? local.config.locations[local.location]["azure"] : local.config.locations[local.location][local.cloud]
}

module "gcp_network" {
  source = "./modules/gcp_network"
  config = local.config
}

module "gcp_security" {
  source   = "./modules/gcp_security"
  config   = local.config
  vpc_name = module.gcp_network.vpc_name
}

module "gcp_vm" {
  source         = "./modules/gcp_vm"
  config         = local.config
  subnetwork     = module.gcp_network.subnet_id
  ssh_public_key = file(var.ssh_public_key_path)
}

# gcp_lb — TCP Load Balancer across all 3 k3s nodes.
module "gcp_lb" {
  source  = "./modules/gcp_lb"
  config  = local.config
  network = module.gcp_network.vpc_name
  k3s_instance_zones = {
    "k3s-server-1" = local.config.locations[local.general.location].gcp.zones.primary
    "k3s-server-2" = local.config.locations[local.general.location].gcp.zones.primary
    "k3s-server-3" = local.config.locations[local.general.location].gcp.zones.secondary
  }
}

module "gcp_sql" {
  source     = "./modules/gcp_sql"
  config     = local.config
  network_id = module.gcp_network.vpc_id
}

module "azure_network" {
  source = "./modules/azure_network"
  config = local.config
}

module "azure_security" {
  source     = "./modules/azure_security"
  config     = local.config
  vnet_name  = module.azure_network.vnet_name
  depends_on = [module.azure_network]
}

module "azure_vm" {
  source              = "./modules/azure_vm"
  config              = local.config
  ssh_public_key      = file(var.ssh_public_key_path)
  public_subnet_id    = module.azure_network.public_subnet_id
  public_subnet_b_id  = module.azure_network.public_subnet_b_id
  private_subnet_id   = module.azure_network.private_subnet_id
  private_subnet_b_id = module.azure_network.private_subnet_b_id
  jump_host_nsg_id    = module.azure_security.jump_host_nsg_id
  internal_nsg_id     = module.azure_security.internal_nsg_id
  web_nsg_id          = module.azure_security.web_nsg_id
  gateway_nsg_id      = module.azure_security.gateway_nsg_id
  depends_on          = [module.azure_network, module.azure_security]
}

module "azure_lb" {
  source     = "./modules/azure_lb"
  config     = local.config
  ui_nic_id  = module.azure_vm.ui_nic_id
  depends_on = [module.azure_network, module.azure_vm]
}

module "azure_db" {
  source     = "./modules/azure_db"
  config     = local.config
  vnet_id    = module.azure_network.vnet_id
  vnet_name  = module.azure_network.vnet_name
  depends_on = [module.azure_network]
}

module "aws_network" {
  source = "./modules/aws_network"
  config = local.config
}

module "aws_security" {
  source = "./modules/aws_security"
  config = local.config
  vpc_id = module.aws_network.vpc_id
}

module "aws_vm" {
  source              = "./modules/aws_vm"
  config              = local.config
  ssh_public_key      = file(var.ssh_public_key_path)
  public_subnet_id    = module.aws_network.public_subnet_id
  private_subnet_id   = module.aws_network.private_subnet_id
  public_subnet_b_id  = module.aws_network.public_subnet_b_id
  private_subnet_b_id = module.aws_network.private_subnet_b_id
  jump_host_sg_id     = module.aws_security.jump_host_sg_id
  internal_sg_id      = module.aws_security.internal_sg_id
  web_sg_id           = module.aws_security.web_sg_id
  gateway_sg_id       = module.aws_security.gateway_sg_id
  k3s_sg_id           = module.aws_security.k3s_sg_id 
  iam_instance_profile = module.aws_monitoring_iam.instance_profile_name
}

module "aws_lb" {
  source             = "./modules/aws_lb"
  config             = local.config
  vpc_id             = module.aws_network.vpc_id
  public_subnet_id   = module.aws_network.public_subnet_id
  public_subnet_b_id = module.aws_network.public_subnet_b_id
  k3s_instance_ids   = module.aws_vm.k3s_instance_ids
}

module "aws_rds" {
  source              = "./modules/aws_rds"
  config              = local.config
  private_subnet_id   = module.aws_network.private_subnet_id
  private_subnet_b_id = module.aws_network.private_subnet_b_id
  rds_sg_id           = module.aws_security.rds_sg_id
}



# --- Monitoring modules ---

module "aws_monitoring_alerting" {
  source      = "./modules/aws_monitoring/alerting"
  topic_name  = "coinops-alerts"
  alert_email = var.alert_email
}

module "aws_monitoring_logs" {
  source      = "./modules/aws_monitoring/logs"
  bucket_name = "coinops-alb-logs-penina"
  account_id  = var.aws_account_id
}

module "aws_monitoring_iam" {
  source = "./modules/aws_monitoring/iam"
}

module "aws_monitoring_ec2_alarms" {
  source        = "./modules/aws_monitoring/ec2_alarms"
  instance_ids  = module.aws_vm.k3s_instance_ids
  sns_topic_arn = module.aws_monitoring_alerting.sns_topic_arn
  cpu_threshold = 80
  depends_on    = [module.aws_monitoring_alerting]
}

module "aws_monitoring_alb_alarms" {
  source                  = "./modules/aws_monitoring/alb_alarms"
  sns_topic_arn           = module.aws_monitoring_alerting.sns_topic_arn
  alb_arn_suffix          = module.aws_lb.alb_arn_suffix
  target_group_arn_suffix = module.aws_lb.target_group_arn_suffix
  healthy_host_threshold  = 2
  depends_on              = [module.aws_monitoring_alerting]
}

module "aws_monitoring_log_metrics" {
  source        = "./modules/aws_monitoring/log_metrics"
  sns_topic_arn = module.aws_monitoring_alerting.sns_topic_arn
  depends_on    = [module.aws_monitoring_alerting]
}

module "aws_monitoring_dashboard" {
  source                  = "./modules/aws_monitoring/dashboard"
  instance_ids            = module.aws_vm.k3s_instance_ids
  alb_arn_suffix          = module.aws_lb.alb_arn_suffix
  target_group_arn_suffix = module.aws_lb.target_group_arn_suffix
  depends_on              = [module.aws_lb, module.aws_vm]
  region = local.config.locations[local.general.location].aws.region
}

module "aws_monitoring_agent" {
  source = "./modules/aws_monitoring/agent"
  region = local.config.locations[local.general.location].aws.region
}

# --- EKS module ---
module "aws_eks" {
  source = "./modules/aws_eks"
  vpc_id = module.aws_network.vpc_id
  subnet_ids = [
    module.aws_network.public_subnet_id,
    module.aws_network.public_subnet_b_id,
    module.aws_network.private_subnet_id,
    module.aws_network.private_subnet_b_id,
  ]
  depends_on = [module.aws_network]
}

module "aws_codebuild" {
  source         = "./modules/aws_codebuild"
  aws_account_id = var.aws_account_id
}