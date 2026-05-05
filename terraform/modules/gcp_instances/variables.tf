variable "instances" {
  type        = any
  description = "Map of VM instances from config.json (keyed by VM name). If empty, a minimal fallback instance is created."
  default     = {}

  validation {
    condition = alltrue([
      for name in keys(var.instances) : can(regex("^[a-z][a-z0-9-]{0,61}[a-z0-9]$", name))
    ])
    error_message = "Instance names must start with a lowercase letter, contain only lowercase letters, numbers, and hyphens, and be 2-63 characters long."
  }
}

variable "defaults" {
  type        = any
  description = "General defaults from config.json."
  default     = {}
}

variable "cloud_defaults" {
  type        = any
  description = "Cloud-specific defaults from gcp.json."
  default     = {}
}

variable "instance_sizes" {
  type        = map(string)
  description = "Mapping of instance size labels to GCP machine types."
  default     = {}
}

variable "network_id" {
  type        = string
  description = "VPC network ID."
}

variable "subnet_ids" {
  type        = map(string)
  description = "Map of subnet name to subnet ID."
}
