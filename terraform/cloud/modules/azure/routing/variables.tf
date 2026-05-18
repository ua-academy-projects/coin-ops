variable "resource_group_name" {
  type = string
}

variable "route" {
  type = object({
    name              = string
    destination_range = string
    next_hop_ip       = string
  })
}

variable "private_subnet_ids" {
  type = map(string)
}
