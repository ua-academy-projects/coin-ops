variable "enabled_clouds" {
  type        = set(string)
  description = "Set of clouds to deploy to. Supported: gcp, aws."
  default     = ["gcp"]

  validation {
    condition = alltrue([
      for cloud in var.enabled_clouds : contains(["gcp", "aws"], cloud)
    ])
    error_message = "Supported clouds: \"gcp\", \"aws\"."
  }

  validation {
    condition     = length(var.enabled_clouds) > 0
    error_message = "At least one cloud must be enabled."
  }
}

variable "gcp_project_id" {
  type        = string
  description = "GCP project ID (required when deploying to GCP)"
  default     = ""
}

variable "gcp_region" {
  type        = string
  description = "GCP region for resources"
  default     = "europe-central2"
}

variable "aws_region" {
  type        = string
  description = "AWS region for resources"
  default     = "eu-north-1"
}

variable "ssh_public_key_path" {
  type        = string
  description = "Path to SSH public key used for all cloud instances (GCP metadata ssh-keys, AWS key pair)."
  default     = "~/.ssh/ssh-key-coin-ops.pub"
}
