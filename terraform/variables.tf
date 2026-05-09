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

variable "cloudflare_api_token" {
  type        = string
  description = "Cloudflare API Token with DNS:Edit permissions"
  sensitive   = true
  default     = ""

  validation {
    condition     = !var.seed_secret_manager || trimspace(var.cloudflare_api_token) != ""
    error_message = "cloudflare_api_token must be set when seed_secret_manager=true."
  }
}

variable "cloudflare_zone_id" {
  type        = string
  description = "Cloudflare Zone ID for the domain"
  default     = ""
}

variable "app_domain" {
  type        = string
  description = "Root domain for the application (e.g. coinops-d.pp.ua)"
  default     = "coinops.test"
}

variable "ssh_public_key_path" {
  type        = string
  description = "Path to SSH public key used for all cloud instances (GCP metadata ssh-keys, AWS key pair)."
  default     = "~/.ssh/ssh-key-coin-ops.pub"
}

variable "db_password" {
  description = "Password for the CloudSQL database user"
  type        = string
  sensitive   = true
  default     = ""

  validation {
    condition     = !var.seed_secret_manager || trimspace(var.db_password) != ""
    error_message = "db_password must be set when seed_secret_manager=true."
  }
}

variable "rabbitmq_password" {
  description = "Password for RabbitMQ"
  type        = string
  sensitive   = true
  default     = ""

  validation {
    condition     = !var.seed_secret_manager || trimspace(var.rabbitmq_password) != ""
    error_message = "rabbitmq_password must be set when seed_secret_manager=true."
  }
}

variable "ghcr_token" {
  description = "GitHub Container Registry PAT"
  type        = string
  sensitive   = true
  default     = ""

  validation {
    condition     = !var.seed_secret_manager || trimspace(var.ghcr_token) != ""
    error_message = "ghcr_token must be set when seed_secret_manager=true."
  }
}

variable "seed_secret_manager" {
  description = "When true, seed/update GCP Secret Manager from local bootstrap secrets input."
  type        = bool
  default     = false
}
