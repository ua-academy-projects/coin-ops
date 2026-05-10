# variables.tf


# access

variable "ssh_user" {
  type = string
}

variable "ssh_public_key_path" {
  type = string
}


# network

variable "network_name" {
  type = string
}

variable "subnetworks" {
  type = map(string)
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
    can_ip_forward = bool
  }))
}
