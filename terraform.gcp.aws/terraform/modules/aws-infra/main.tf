locals {
  bastion_vm          = one([for name, vm in var.config.vms : merge(vm, { name = name }) if vm.role == "bastion"])
  web_vm              = one([for name, vm in var.config.vms : merge(vm, { name = name }) if contains(vm.tags, var.config.load_balancer.target_tag)])
  private_target_tags = distinct(flatten([for vm in values(var.config.vms) : vm.tags if vm.role == "private"]))
}

module "vpc" {
  source = "../vpc"
  cloud  = "aws"
  config = var.config
}

module "firewall" {
  source               = "../firewall"
  cloud                = "aws"
  network_name         = var.config.network.name
  vpc_id               = module.vpc.vpc_id
  allowed_source_cidr  = var.config.ssh.allowed_source_cidr
  bastion_tags         = local.bastion_vm.tags
  private_target_tags  = local.private_target_tags
  web_target_tags      = local.web_vm.tags
  load_balancer_port   = var.config.load_balancer.port
  private_service_cidr = var.config.network.cidr
}

module "ssh_key" {
  source          = "../ssh-key"
  cloud           = "aws"
  network_name    = var.config.network.name
  ssh_user        = var.config.ssh.user
  public_key_path = var.config.ssh.public_key_path
}

module "instance" {
  for_each                      = var.config.vms
  source                        = "../instance"
  cloud                         = "aws"
  config                        = var.config
  name                          = each.key
  vm                            = each.value
  ssh_key                       = var.ssh_key
  gcp_subnet_id                 = null
  aws_public_subnet_id          = module.vpc.public_subnet_id
  aws_private_subnet_id         = module.vpc.private_subnet_id
  aws_key_name                  = module.ssh_key.key_name
  aws_bastion_security_group_id = module.firewall.bastion_security_group_id
  aws_private_security_group_id = module.firewall.private_security_group_id
}

module "load_balancer" {
  source                 = "../load-balancer"
  cloud                  = "aws"
  name                   = var.config.network.name
  port                   = var.config.load_balancer.port
  gcp_region             = null
  gcp_target_self_link   = null
  aws_public_subnet_ids  = module.vpc.public_subnet_ids
  aws_security_group_id  = module.firewall.load_balancer_security_group_id
  aws_target_instance_id = module.instance[local.web_vm.name].id
}
module "rds" {
  source                    = "../rds"
  cloud                     = "aws"
  name                      = var.config.network.name
  private_subnet_ids        = module.vpc.private_subnet_ids
  vpc_id                    = module.vpc.vpc_id
  private_security_group_id = module.firewall.private_security_group_id
  db_name                   = "cognitor"
  db_user                   = "cognitor"
  db_password               = var.db_password
}
