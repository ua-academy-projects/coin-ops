variable "resource_group_name" {
  type = string
}

variable "network" {
  type = object({
    name = string
    cidr = string
    subnets = map(object({
      cidr      = string
      placement = string
      exposure  = string
    }))
  })

  validation {
    condition = alltrue([
      for _, subnet in var.network.subnets : contains(["public", "private"], subnet.exposure)
    ])
    error_message = "Each subnet exposure must be either \"public\" or \"private\"."
  }
}

variable "nat_route" {
  type = object({
    name              = string
    destination_range = string
    next_hop_ip       = string
  })
  default  = null
  nullable = true
}
