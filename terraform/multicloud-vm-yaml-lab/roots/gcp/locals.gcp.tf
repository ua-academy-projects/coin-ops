locals {
  bastion_target_tags = local.intent_instances[local.bastion_name].tags

  private_target_tags = distinct(flatten([
    for name, vm in local.intent_instances :
    vm.tags
    if name != local.bastion_name
  ]))

  gcp_vm_defaults = {
    machine_type        = local.raw.catalog.sizes[local.default_size_key].gcp
    image               = local.raw.catalog.images[local.default_image_key].gcp
    disk_size_gb        = local.raw.defaults.disk_size_gb
    ssh_user            = local.raw.ssh.user
    ssh_public_key_path = local.raw.ssh.public_key_path
  }

  gcp_instances = {
    for name, vm in local.intent_instances :
    name => {
      private_ip   = vm.private_ip
      public_ip    = vm.public_ip
      tags         = vm.tags
      machine_type = local.raw.catalog.sizes[vm.size_key].gcp
      image        = local.raw.catalog.images[vm.image_key].gcp
      disk_size_gb = vm.disk_size_gb
    }
  }

  runtime_instances = {
    for name, instance in module.vms.instances :
    name => {
      name       = instance.name
      private_ip = instance.internal_ip
      public_ip  = instance.external_ip
    }
  }

  private_instances = {
    for name, instance in local.runtime_instances :
    name => instance
    if name != local.bastion_name
  }

  ssh_bastion_alias = "${local.raw.name_prefix}-bastion"
  ssh_known_hosts   = "~/.ssh/known_hosts_gcp_lab"
}
