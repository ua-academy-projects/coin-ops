variable "private_route_table_id" {
  type        = string
  description = "ID of the private route table created by aws_network. The module only adds a default route to this table."
  default     = ""
}

variable "nat_network_interface_id" {
  type        = string
  description = "Primary ENI ID of the NAT instance (jump-host)."
  default     = ""
}

variable "destination_cidr" {
  type        = string
  description = "Destination CIDR for private default route."
  default     = "0.0.0.0/0"
}
