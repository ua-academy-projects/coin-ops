variable "vpc_name" {
  type    = string
  default = "vpc-network"
}

variable "region" {
  type    = string
  default = "europe-central2"
}

variable "subnets" {
  type        = any
  description = "Map of subnets from networks.json (keyed by subnet name)."
  default     = {}
}
