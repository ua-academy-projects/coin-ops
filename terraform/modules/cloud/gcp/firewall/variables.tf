variable "network_id" {
  type        = string
  description = "VPC network ID to attach firewall rules to."
}

variable "firewall_rules" {
  type        = any
  description = "Map of firewall rules from networks.json."
  default     = {}
}
