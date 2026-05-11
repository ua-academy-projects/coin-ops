locals {
  aws_instances = {
    for name, vm in local.intent_instances :
    name => {
      name          = vm.name
      role          = vm.role
      private_ip    = vm.private_ip
      public_ip     = vm.public_ip
      tags          = vm.tags
      instance_type = local.raw.catalog.sizes[vm.size_key].aws
      image_key     = vm.image_key
      disk_size_gb  = vm.disk_size_gb
    }
  }

  aws_image_catalog = {
    for image_key, image_config in local.raw.catalog.images :
    image_key => image_config.aws
  }

  runtime_instances = {
    for name, instance in module.vms.instances :
    name => {
      name       = local.intent_instances[name].name
      private_ip = instance.private_ip
      public_ip  = instance.public_ip
    }
  }

  private_instances = {
    for name, instance in local.runtime_instances :
    name => instance
    if name != local.bastion_name
  }

  ssh_bastion_alias = "${local.raw.name_prefix}-bastion"
  ssh_known_hosts   = "~/.ssh/known_hosts_aws_lab"
}
