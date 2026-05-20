variable "name_prefix" {
  type = string
}

variable "safe_prefix" {
  type = string
}

variable "unique_suffix" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "network_id" {
  type = string
}

variable "database_subnet_id" {
  type = string
}

variable "runtime" {
  type = any
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "zones" {
  type = list(string)
}
