variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "name" {
  description = "VM instance name"
  type        = string

  validation {
    condition     = can(regex("^[a-z]([-a-z0-9]{0,61}[a-z0-9])?$", var.name))
    error_message = "VM name must be lowercase, start with a letter, max 63 chars."
  }
}

variable "zone" {
  description = "GCP zone"
  type        = string
}

variable "machine_type" {
  description = "Machine type for the VM"
  type        = string
  default     = "e2-micro"

  validation {
    condition     = contains(["e2-micro", "e2-small", "e2-medium"], var.machine_type)
    error_message = "Machine type must be one of: e2-micro, e2-small, e2-medium."
  }
}

variable "os_image" {
  description = "Boot disk OS image"
  type        = string
  default     = "debian-cloud/debian-12"
}

variable "disk_size_gb" {
  description = "Boot disk size in GB"
  type        = number
  default     = 10

  validation {
    condition     = var.disk_size_gb >= 10 && var.disk_size_gb <= 200
    error_message = "Disk size must be between 10 and 200 GB."
  }
}

variable "disk_type" {
  description = "Boot disk type"
  type        = string
  default     = "pd-standard"

  validation {
    condition     = contains(["pd-standard", "pd-balanced", "pd-ssd"], var.disk_type)
    error_message = "Disk type must be one of: pd-standard, pd-balanced, pd-ssd."
  }
}

variable "network_self_link" {
  description = "Self-link of the VPC network"
  type        = string
}

variable "subnet_self_link" {
  description = "Self-link of the subnet"
  type        = string
}

variable "assign_public_ip" {
  description = "Whether to assign a public IP to the VM"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Network tags for firewall rules"
  type        = list(string)
  default     = []
}

variable "labels" {
  description = "Labels to apply to the VM"
  type        = map(string)
  default     = {}
}

variable "environment" {
  description = "Environment label"
  type        = string
  default     = "learning"
}

variable "ssh_user" {
  description = "SSH username to create on the VM"
  type        = string
  default     = "terraform"
}

variable "ssh_public_key" {
  description = "SSH public key content for VM access"
  type        = string
  sensitive   = true
}

variable "ssh_port" {
  description = "SSH port to configure on the VM"
  type        = number
  default     = 47832

  validation {
    condition     = var.ssh_port >= 1024 && var.ssh_port <= 65535
    error_message = "SSH port must be between 1024 and 65535."
  }
}
