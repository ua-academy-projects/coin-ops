variable "vpc_name" {
  type        = string
  description = "Virtual network name."
}

variable "vpc_cidr" {
  type        = string
  description = "Virtual network CIDR."
}

variable "subnets" {
  type        = any
  description = "Map of subnet definitions from terraform/config/networks.json."
  default     = {}
}

variable "location" {
  type        = string
  description = "Azure location for network resources."
}

variable "resource_group_name" {
  type        = string
  description = "Resource group name for Azure network resources."
}
