variable "resource_group_name" {
  type        = string
  description = "Resource group name for Azure route resources."
}

variable "location" {
  type        = string
  description = "Azure location for Azure route resources."
}

variable "subnet_ids" {
  type        = map(string)
  description = "Map of private subnet IDs that should use the NAT VM."
}

variable "route_table_name" {
  type        = string
  description = "Route table name."
}

variable "destination_cidr" {
  type        = string
  description = "Destination CIDR to route through the NAT VM."
}

variable "next_hop_ip" {
  type        = string
  description = "Private IP of the NAT VM."
}
