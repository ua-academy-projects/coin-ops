# variables.tf

variable "network_id" {
  type = string
}

variable "private_subnet_ids" {
  type = map(string)
}

variable "route" {
  type = object({
    name              = string
    destination_range = string
    instance_workload = string
    target_tags       = list(string)
  })
}

variable "next_hop_interface_ids" {
  type = map(string)
}
