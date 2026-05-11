locals {
  raw = yamldecode(file("${path.module}/../../config/lab.yaml"))

  location_key = local.raw.location
  aws_location = local.raw.catalog.locations[local.location_key].aws

  default_network_key = local.raw.defaults.network
  default_size_key    = local.raw.defaults.size
  default_image_key   = local.raw.defaults.image

  network = merge(
    {
      name        = "${local.raw.name_prefix}-${local.default_network_key}-vpc"
      subnet_name = "${local.raw.name_prefix}-${local.default_network_key}-subnet"
    },
    local.raw.networks[local.default_network_key]
  )

  intent_instances = {
    for name, vm in local.raw.instances :
    name => {
      key          = name
      name         = "${local.raw.name_prefix}-${name}"
      role         = vm.role
      role_config  = local.raw.roles[vm.role]
      private_ip   = vm.private_ip
      public_ip    = local.raw.roles[vm.role].public_ip
      size_key     = lookup(vm, "size", local.default_size_key)
      image_key    = lookup(vm, "image", local.default_image_key)
      disk_size_gb = lookup(vm, "disk_size_gb", local.raw.defaults.disk_size_gb)
      network_key  = lookup(vm, "network", local.default_network_key)
      tags         = lookup(local.raw.roles[vm.role], "tags", [vm.role])
    }
  }

  bastion_names = [
    for name, vm in local.intent_instances :
    name
    if vm.public_ip
  ]

  bastion_name = one(local.bastion_names)
}
