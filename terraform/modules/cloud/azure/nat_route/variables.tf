variable "resource_group_name" {
  type        = string
  description = "Resource group name for Azure route resources."
}

variable "location" {
  type        = string
  description = "Azure location for Azure route resources."
}

variable "private_subnet_ids" {
  type        = map(string)
  description = "Map of private subnet IDs that should use the NAT VM for default and remote routes."
}

variable "public_subnet_ids" {
  type        = map(string)
  description = "Map of public subnet IDs that should use the NAT VM for remote cloud CIDRs."
  default     = {}
}

variable "route_table_name" {
  type        = string
  description = "Route table name."
}

variable "private_routes" {
  type        = map(any)
  description = "Map of route name to route configuration for private subnets."
  default     = {}
}

variable "public_routes" {
  type        = map(any)
  description = "Map of route name to route configuration for public subnets."
  default     = {}
}

variable "next_hop_ip" {
  type        = string
  description = "Private IP of the NAT VM."
}
