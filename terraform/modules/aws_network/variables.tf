variable "vpc_name" {
  type    = string
  default = "vpc-network"
}

variable "vpc_cidr" {
  type    = string
  default = "10.10.0.0/16"
}

variable "subnets" {
  type        = any
  description = "Map of subnets from networks.json (keyed by subnet name)."
  default     = {}
}

variable "zone" {
  type        = string
  description = "AWS availability zone for subnets."
  default     = "eu-north-1a"
}
