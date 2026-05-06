variable "vpc_id" {
  type        = string
  description = "VPC ID to create security groups in."
}

variable "firewall_rules" {
  type        = any
  description = "Map of firewall rules from networks.json."
  default     = {}
}

variable "egress_cidrs" {
  type        = list(string)
  description = "Allowed egress CIDRs for all security groups."
  default     = ["0.0.0.0/0"]
}
