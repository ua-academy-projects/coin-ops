variable "private_subnet_ids" {
  type        = map(string)
  description = "Map of private subnet name to subnet ID (from aws_network output)."
  default     = {}
}

variable "nat_network_interface_id" {
  type        = string
  description = "Primary ENI ID of the NAT instance (jump-host)."
  default     = ""
}

variable "vpc_id" {
  type        = string
  description = "VPC ID for route table creation."
  default     = ""
}

variable "destination_cidr" {
  type        = string
  description = "Destination CIDR for private default route."
  default     = "0.0.0.0/0"
}

variable "route_table_name" {
  type        = string
  description = "Name tag for private route table."
  default     = "private-default-via-jump"
}
