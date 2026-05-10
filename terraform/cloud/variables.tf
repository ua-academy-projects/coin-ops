# variables.tf


# general

variable "cloud" {
  type = string

  validation {
    condition     = contains(["gcp", "aws"], var.cloud)
    error_message = "Cloud must be either \"gcp\" or \"aws\"."
  }
}


# network

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


# security 

variable "security_rules" {
  type = map(object({
    description      = string
    direction        = string
    priority         = number
    protocol         = string
    ports            = list(string)
    cidr_blocks      = list(string)
    source_workloads = list(string)
    target_workloads = list(string)
  }))
}
