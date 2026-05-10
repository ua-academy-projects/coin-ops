# variables.tf


# general

variable "cloud" {
  type = string

  validation {
    condition     = contains(["gcp", "aws"], var.cloud)
    error_message = "Cloud must be either \"gcp\" or \"aws\"."
  }
}

variable "ssh_public_key_path" {
  type    = string
  default = "~/.ssh/coinops_gcp.pub"
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

variable "nat_route" {
  type = object({
    name              = string
    destination_range = string
    instance_workload = string
    target_tags       = list(string)
  })
  default  = null
  nullable = true
}


# instances

variable "workloads" {
  type = map(object({
    instance_type   = string
    image_family    = string
    placement       = string
    subnet          = string
    tags            = list(string)
    disk_size_gb    = number
    public_ip       = bool
    can_ip_forward  = bool
    service_account = optional(string)
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


# secrets

variable "gsm_secrets" {
  type = map(object({
    secret_id = string
  }))
  default = {}
}

variable "gcp_service_accounts" {
  type = map(object({
    account_id   = string
    display_name = string
  }))
  default = {}
}

variable "gcp_secret_access" {
  type = map(object({
    service_account = string
    secrets         = list(string)
  }))
  default = {}
}
