variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "GCP zone"
  type        = string
  default     = "us-central1-a"
}

variable "bucket_name" {
  description = "GCS bucket name for Terraform remote state"
  type        = string
}

variable "network_name" {
  description = "Name of the VPC network"
  type        = string
  default     = "terraform-network"

  validation {
    condition     = can(regex("^[a-z]([-a-z0-9]{0,61}[a-z0-9])?$", var.network_name))
    error_message = "Network name must be lowercase, start with a letter, and contain only letters, digits, hyphens (max 63 chars)."
  }
}

variable "subnet_cidr" {
  description = "CIDR range for the subnet"
  type        = string
  default     = "10.0.0.0/24"

  validation {
    condition     = can(cidrnetmask(var.subnet_cidr))
    error_message = "Subnet CIDR must be a valid IPv4 CIDR block."
  }
}

variable "machine_type" {
  description = "Machine type for all VMs"
  type        = string
  default     = "e2-micro"

  validation {
    condition     = contains(["e2-micro", "e2-small", "e2-medium"], var.machine_type)
    error_message = "Machine type must be one of: e2-micro, e2-small, e2-medium."
  }
}

variable "environment" {
  description = "Environment label"
  type        = string
  default     = "learning"

  validation {
    condition     = contains(["learning", "dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: learning, dev, staging, prod."
  }
}

variable "ssh_source_ip" {
  description = "Your public IP address for SSH access to jump host (CIDR format, e.g. 203.0.113.5/32)"
  type        = string

  validation {
    condition     = can(cidrnetmask(var.ssh_source_ip))
    error_message = "SSH source IP must be a valid CIDR block (e.g. 203.0.113.5/32)."
  }
}