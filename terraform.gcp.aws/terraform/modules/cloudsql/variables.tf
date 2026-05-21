variable "name" {
  type = string
}

variable "region" {
  type = string
}

variable "network_id" {
  type = string
}

variable "db_name" {
  type = string
}

variable "db_user" {
  type = string
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "tier" {
  type    = string
  default = "db-custom-1-3840"
}

variable "disk_size_gb" {
  type    = number
  default = 20
}

variable "private_service_range_prefix_length" {
  type    = number
  default = 16
}
