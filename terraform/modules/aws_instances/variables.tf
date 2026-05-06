variable "instances" {
  type        = any
  description = "Map of VM instances from config.json (keyed by VM name). If empty, a minimal fallback instance is created."
  default     = {}
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
