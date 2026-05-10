# locals.tf

locals {
  mappings = jsondecode(file("${path.module}/mappings.json"))

  subnets = {
    for key, subnet in var.network.subnets : key => {
      cidr                    = subnet.cidr
      availability_zone       = local.mappings.placement[subnet.placement].subnet_location
      map_public_ip_on_launch = local.mappings.subnet_exposure[subnet.exposure].map_public_ip_on_launch
    }
  }
}
