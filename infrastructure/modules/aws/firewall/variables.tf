variable "name" {
  description = "Security group name"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "description" {
  description = "Security group description"
  type        = string
  default     = ""
}

variable "ingress_rules" {
  description = "Ingress rules for the security group"
  type = list(object({
    protocol    = string
    from_port   = number
    to_port     = number
    cidr_blocks = list(string)
    description = string
  }))
  default = []
}
