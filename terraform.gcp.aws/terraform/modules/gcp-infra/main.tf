locals {
  bastion_vm          = one([for name, vm in var.config.vms : merge(vm, { name = name }) if vm.role == "bastion"])
  web_vm              = one([for name, vm in var.config.vms : merge(vm, { name = name }) if contains(vm.tags, var.config.load_balancer.target_tag)])
  private_target_tags = distinct(flatten([for vm in values(var.config.vms) : vm.tags if vm.role == "private"]))
}

module "vpc" {
  source = "../vpc"
  cloud  = "gcp"
  config = var.config
}

module "firewall" {
  source               = "../firewall"
  cloud                = "gcp"
  network_name         = module.vpc.network_name
  vpc_id               = null
  allowed_source_cidr  = var.config.ssh.allowed_source_cidr
  bastion_tags         = local.bastion_vm.tags
  private_target_tags  = local.private_target_tags
  web_target_tags      = local.web_vm.tags
  load_balancer_port   = var.config.load_balancer.port
  private_service_cidr = null
}

module "ssh_key" {
  source          = "../ssh-key"
  cloud           = "gcp"
  network_name    = var.config.network.name
  ssh_user        = var.config.ssh.user
  public_key_path = var.config.ssh.public_key_path
}

module "instance" {
  for_each                      = var.config.vms
  source                        = "../instance"
  cloud                         = "gcp"
  config                        = var.config
  name                          = each.key
  vm                            = each.value
  ssh_key                       = var.ssh_key
  gcp_subnet_id                 = module.vpc.subnet_id
  aws_public_subnet_id          = null
  aws_private_subnet_id         = null
  aws_key_name                  = null
  aws_bastion_security_group_id = null
  aws_private_security_group_id = null
}

module "load_balancer" {
  source                 = "../load-balancer"
  cloud                  = "gcp"
  name                   = var.config.network.name
  port                   = var.config.load_balancer.port
  gcp_region             = var.config.project.gcp.region
  gcp_target_self_link   = module.instance[local.web_vm.name].self_link
  aws_public_subnet_ids  = null
  aws_security_group_id  = null
  aws_target_instance_id = null
}
