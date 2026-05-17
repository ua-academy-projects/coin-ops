variable "name" {
  description = "VPC name"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnets" {
  description = "Map of subnets to create inside this VPC"
  type = map(object({
    cidr              = string
    availability_zone = string
  }))
  default = {}
}
