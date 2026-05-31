# locals.tf

locals {
  mappings = jsondecode(file("${path.module}/mappings.json"))

  subnets = {
    for key, subnet in var.network.subnets : key => {
      cidr      = subnet.cidr
      location  = local.mappings.placement[subnet.placement].subnet_location
      exposure  = subnet.exposure
      is_public = local.mappings.subnet_exposure[subnet.exposure].is_public
    }
  }

  private_subnets = {
    for key, subnet in local.subnets : key => subnet
    if !subnet.is_public
  }
}
