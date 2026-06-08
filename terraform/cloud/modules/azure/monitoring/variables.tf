# variables.tf

variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "name" {
  type = string
}

variable "vm_ids" {
  type = map(string)
}

variable "postgresql_server_id" {
  type    = string
  default = null
}


# alerts

variable "vm_cpu_alert_enabled" {
  type    = bool
  default = true
}

variable "postgresql_cpu_alert_enabled" {
  type    = bool
  default = true
}

variable "postgresql_storage_alert_enabled" {
  type    = bool
  default = true
}

variable "postgresql_connections_alert_enabled" {
  type    = bool
  default = true
}

variable "postgresql_failed_connections_alert_enabled" {
  type    = bool
  default = true
}
