variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "name" {
  description = "VPC network name"
  type        = string

  validation {
    condition     = can(regex("^[a-z]([-a-z0-9]{0,61}[a-z0-9])?$", var.name))
    error_message = "Network name must be lowercase, start with a letter, max 63 chars."
  }
}

variable "description" {
  description = "VPC network description"
  type        = string
  default     = ""
}

variable "subnets" {
  description = "Map of subnets to create inside this VPC"
  type = map(object({
    cidr   = string
    region = string
  }))
  default = {}
}