# locals.tf

locals {
  mappings = jsondecode(file("${path.module}/mappings.json"))

  subnets = {
    for key, subnet in var.network.subnets : key => {
      cidr     = subnet.cidr
      location = local.mappings.placement[subnet.placement].subnet_location
      exposure = subnet.exposure
    }
  }
}
