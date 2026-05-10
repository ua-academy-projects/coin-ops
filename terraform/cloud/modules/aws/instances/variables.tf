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

variable "workloads" {
  type = map(object({
    instance_type = string
    image_family  = string
    placement     = string
    subnet        = string
    tags          = list(string)
    disk_size_gb  = number
    public_ip     = bool
  }))
}
