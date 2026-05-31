# variables.tf

variable "network_name" {
  type = string
}

variable "route" {
  type = object({
    name              = string
    destination_range = string
    instance_workload = string
    target_tags       = list(string)
  })
}

variable "next_hop_instances" {
  type = map(string)
}
