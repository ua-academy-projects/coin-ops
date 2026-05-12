variable "placement" {
  type = string
}

variable "network_name" {
  type = string
}

variable "db_password_secret_id" {
  type = string
}

variable "instance" {
  type = object({
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
}

variable "database" {
  type = object({
    name = string
  })
}

variable "user" {
  type = object({
    name = string
  })
}
