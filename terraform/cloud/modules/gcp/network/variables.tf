# variables.tf

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
}

variable "nat_route" {
  type = object({
    name              = string
    destination_range = string
    target_tags       = list(string)
    next_hop_instance = string
  })
  default  = null
  nullable = true
}
