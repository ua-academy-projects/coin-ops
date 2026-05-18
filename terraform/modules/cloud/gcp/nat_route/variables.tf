variable "network_id" {
  type        = string
  description = "GCP VPC network ID."
}

variable "routes" {
  type        = map(any)
  description = "Map of route name to route configuration (destination_cidr, optional priority, optional target_tags)."
  default     = {}
}

variable "next_hop_ip" {
  type        = string
  description = "Private IP of NAT hop instance."
  default     = ""
}
