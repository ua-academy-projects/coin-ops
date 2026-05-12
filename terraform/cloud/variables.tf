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

variable "service_accounts" {
  type = map(object({
    name         = string
    display_name = string
  }))
  default = {}
}

variable "secret_access" {
  type = map(object({
    service_account = string
    secrets         = list(string)
  }))
  default = {}
}

variable "sql" {
  type = object({
    placement = string
    instance = object({
      name                = string
      edition             = string
      database_version    = string
      instance_type       = string
      availability_type   = string
      disk_type           = string
      disk_size           = number
      disk_autoresize     = bool
      deletion_protection = bool
      backup_enabled      = bool
      pitr_enabled        = bool
      private_range_name  = string
      private_range_cidr  = number
    })
    database = object({
      name = string
    })
    user = object({
      name = string
    })
  })
  default  = null
  nullable = true

  validation {
    condition     = var.sql == null || contains(["enterprise", "enterprise_plus"], var.sql.instance.edition)
    error_message = "sql.instance.edition must be one of: enterprise, enterprise_plus."
  }

  validation {
    condition     = var.sql == null || contains(["postgres_16"], var.sql.instance.database_version)
    error_message = "sql.instance.database_version must be one of: postgres_16."
  }

  validation {
    condition     = var.sql == null || contains(["economical"], var.sql.instance.instance_type)
    error_message = "sql.instance.instance_type must be one of: economical."
  }

  validation {
    condition     = var.sql == null || contains(["single_zone", "regional"], var.sql.instance.availability_type)
    error_message = "sql.instance.availability_type must be one of: single_zone, regional."
  }

  validation {
    condition     = var.sql == null || contains(["hdd", "ssd"], var.sql.instance.disk_type)
    error_message = "sql.instance.disk_type must be one of: hdd, ssd."
  }
}
