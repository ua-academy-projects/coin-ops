variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "name" {
  description = "Firewall rule name"
  type        = string
}

variable "network_self_link" {
  description = "Self-link of the VPC network"
  type        = string
}

variable "protocol" {
  description = "Protocol for single-protocol rules (tcp, udp, icmp, all)"
  type        = string
  default     = null
}

variable "protocols" {
  description = "List of protocols for multi-protocol rules"
  type        = list(string)
  default     = []
}

variable "ports" {
  description = "List of ports or port ranges (e.g. 22, 8080, 0-65535)"
  type        = list(string)
  default     = []
}

variable "source_ranges" {
  description = "Source CIDR ranges (e.g. 10.0.0.0/24, 0.0.0.0/0)"
  type        = list(string)
  default     = []
}

variable "source_tags" {
  description = "Source network tags"
  type        = list(string)
  default     = []
}

variable "target_tags" {
  description = "Target network tags this rule applies to"
  type        = list(string)
}

variable "description" {
  description = "Human-readable description of the rule"
  type        = string
  default     = ""
}
