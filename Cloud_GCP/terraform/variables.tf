variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
}

variable "zone" {
  description = "GCP zone"
  type        = string
}

variable "credentials_file" {
  description = "Path to service account key"
  type        = string
}

variable "ssh_port" {
  description = "SSH port for all VMs (non-default to reduce automated attacks)"
  type        = string
  default     = "9922"
}

variable "ops_user" {
  description = "Operational user for SSH access — used by Terraform, Ansible, and SSH config"
  type        = string
}
