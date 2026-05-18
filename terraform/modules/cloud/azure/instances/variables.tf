variable "instances" {
  type        = any
  description = "Map of VM instances from terraform/config/instances.json (keyed by VM name). If empty, a minimal fallback instance is created."
  default     = {}
}

variable "defaults" {
  type        = any
  description = "General defaults from terraform/config/general.json."
  default     = {}
}

variable "cloud_defaults" {
  type        = any
  description = "Cloud-specific defaults derived from split JSON config and cloud_mappings.json."
  default     = {}
}

variable "instance_sizes" {
  type        = map(string)
  description = "Mapping of instance size labels to Azure VM sizes."
  default     = {}
}

variable "subnet_ids" {
  type        = map(string)
  description = "Map of subnet name to subnet ID."
}

variable "nsg_ids" {
  type        = map(string)
  description = "Map of role name to network security group ID."
}

variable "asg_ids" {
  type        = map(string)
  description = "Map of role name to application security group ID."
}

variable "ssh_public_key" {
  type        = string
  description = "SSH public key content for Azure Linux VMs."
  default     = ""
}

variable "private_subnet_cidr" {
  type        = string
  description = "CIDR of the private subnet. Injected into startup script templates via templatefile()."
  default     = ""
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR of the cloud VNet. Injected into gateway startup templates for Tailscale-side SNAT."
  default     = ""
}

variable "username" {
  type        = string
  description = "Custom OS user to create on every VM."
  default     = ""
}

variable "ssh_port" {
  type        = number
  description = "SSH port configured in sshd_config via user_init_script template."
  default     = 22
}

variable "project_name" {
  type        = string
  description = "Project name to be used in tags for cloud-native Ansible inventory plugins."
  default     = "coin-ops"
}

variable "resource_group_name" {
  type        = string
  description = "Resource group name for Azure VMs."
}

variable "location" {
  type        = string
  description = "Azure location for Azure VMs."
}
