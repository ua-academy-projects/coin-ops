variable "resource_group_name" {
  type        = string
  description = "Resource group name for Azure security resources."
}

variable "location" {
  type        = string
  description = "Azure location for Azure security resources."
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
