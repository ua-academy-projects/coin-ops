variable "private_route_table_id" {
  type        = string
  description = "ID of the private route table created by aws_network."
  default     = ""
}

variable "public_route_table_id" {
  type        = string
  description = "ID of the public route table created by aws_network."
  default     = ""
}

variable "nat_network_interface_id" {
  type        = string
  description = "Primary ENI ID of the NAT instance (jump-host)."
  default     = ""
}

variable "private_routes" {
  type        = map(any)
  description = "Map of route name to route configuration for the private route table."
  default     = {}
}

variable "public_routes" {
  type        = map(any)
  description = "Map of route name to route configuration for the public route table."
  default     = {}
}
