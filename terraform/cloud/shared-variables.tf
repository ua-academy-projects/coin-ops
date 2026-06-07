# shared-variables.tf
# -> contains all variables needed for cloud-agnostic configuration

# general

variable "config_name" {
  type        = string
  default     = "vm"
  description = "Name of the shared config file in ../../configs without the .json extension."

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]+$", var.config_name))
    error_message = "config_name may only contain letters, numbers, underscores, and hyphens."
  }

}

variable "ssh_public_key_path" {
  type    = string
  default = "~/.ssh/coinops_gcp.pub"
}

variable "ssh_user" {
  type    = string
  default = "deployer"
}
