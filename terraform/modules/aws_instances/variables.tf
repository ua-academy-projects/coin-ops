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
  description = "Cloud-specific defaults from aws.json."
  default     = {}
}

variable "instance_sizes" {
  type        = map(string)
  description = "Mapping of instance size labels to AWS instance types."
  default     = {}
}

variable "subnet_ids" {
  type        = map(string)
  description = "Map of subnet name to subnet ID."
}

variable "sg_ids" {
  type        = map(string)
  description = "Map of role name to security group ID."
}

variable "ssh_public_key" {
  type        = string
  description = "SSH public key content for EC2 key pair."
  default     = ""
}

variable "private_subnet_cidr" {
  type        = string
  description = "CIDR of the private subnet (e.g. 10.10.1.0/24). Injected into startup script templates via templatefile()."
  default     = ""
}

variable "username" {
  type        = string
  description = "Custom OS user to create on every VM (e.g. 'coinops'). Injected into user_init_script template."
  default     = ""
}

variable "ssh_port" {
  type        = number
  description = "SSH port configured in sshd_config via user_init_script template. Also used in generated ssh_config."
  default     = 22
}
