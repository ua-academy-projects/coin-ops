variable "name" {
  description = "VM instance name"
  type        = string
}

variable "machine_type" {
  description = "GCP machine type (e.g., e2-micro, e2-medium)"
  type        = string
}

variable "zone" {
  description = "GCP zone where the VM will be created"
  type        = string
}

variable "image" {
  description = "Boot disk image"
  type        = string
}

variable "disk_size" {
  description = "Boot disk size in GB"
  type        = number
  default     = 10
}

variable "tags" {
  description = "Network tags for firewall rules"
  type        = list(string)
}

variable "subnetwork" {
  description = "Subnetwork ID to attach the VM to"
  type        = string
}

variable "public_ip" {
  description = "Whether to assign an external IP"
  type        = bool
  default     = false
}

variable "ssh_user" {
  description = "Operational user for SSH access"
  type        = string
}

variable "ssh_public_key" {
  description = "SSH public key content"
  type        = string
}

variable "ssh_port" {
  description = "Custom SSH port"
  type        = string
}