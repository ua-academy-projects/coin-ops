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

variable "runtime" {
  type = any
}

variable "app_instances" {
  type = map(any)
}
