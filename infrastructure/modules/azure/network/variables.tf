variable "name" {
  description = "Virtual Network name"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the Resource Group to create for project infrastructure"
  type        = string
}

variable "location" {
  description = "Azure region (e.g. westeurope)"
  type        = string
}

variable "vnet_cidr" {
  description = "CIDR range for the Virtual Network"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnets" {
  description = "Map of subnets to create inside the VNet"
  type = map(object({
    cidr = string
  }))
  default = {}
}

variable "tags" {
  description = "Tags applied to all network resources"
  type        = map(string)
  default     = {}
}
