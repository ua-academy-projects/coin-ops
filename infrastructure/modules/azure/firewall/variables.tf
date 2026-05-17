variable "name" {
  description = "Network Security Group name"
  type        = string
}

variable "resource_group_name" {
  description = "Resource Group where the NSG is created"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "ingress_rules" {
  description = "List of inbound security rules"
  type = list(object({
    name        = string
    priority    = number
    protocol    = string # Tcp, Udp, Icmp, or *
    port        = string # single port, range "80-90", or *
    source      = string # CIDR, or *
    description = optional(string, "")
  }))
  default = []
}

variable "tags" {
  description = "Tags applied to the NSG"
  type        = map(string)
  default     = {}
}
