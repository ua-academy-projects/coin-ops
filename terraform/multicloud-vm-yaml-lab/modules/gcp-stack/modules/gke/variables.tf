variable "name_prefix" {
  type = string
}

variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "network_self_link" {
  type = string
}

variable "gke" {
  type = object({
    enabled           = bool
    node_machine_type = string
    min_nodes         = number
    max_nodes         = number
    release_channel   = string
    subnet_cidr       = string
    pods_cidr         = string
    services_cidr     = string
  })
}
