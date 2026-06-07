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
