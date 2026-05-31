# variables.tf


# network

variable "subnetworks" {
  type = map(string)
}


# security

variable "security_group_ids" {
  type    = map(string)
  default = {}
}


# instances

variable "ssh_user" {
  type = string
}

variable "ssh_public_key_path" {
  type = string
}

variable "workloads" {
  type = map(object({
    roles          = list(string)
    cloud          = optional(string)
    instance_type  = string
    image_family   = string
    placement      = string
    subnet         = string
    tags           = list(string)
    disk_size_gb   = number
    public_ip      = bool
    can_ip_forward = bool
    identity       = optional(string)
    secrets        = optional(list(string))
  }))
}

variable "secrets" {
  type = map(object({
    secret_id = string
  }))
  default = {}
}
