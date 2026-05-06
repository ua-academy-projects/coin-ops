variable "name" {
  type        = string
  description = "Route name."
  default     = "private-default-via-jump"
}

variable "network_id" {
  type        = string
  description = "GCP VPC network ID."
}

variable "destination_cidr" {
  type        = string
  description = "Destination CIDR for NAT route."
  default     = "0.0.0.0/0"
}

variable "priority" {
  type        = number
  description = "Route priority."
  default     = 800
}

variable "target_tags" {
  type        = list(string)
  description = "Network tags this route applies to."
  default     = ["internal-vm"]
}

variable "next_hop_ip" {
  type        = string
  description = "Private IP of NAT hop instance."
  default     = ""
}
