variable "gcp_project_id" {
  type        = string
  description = "Fallback GCP project ID. The canonical value lives in terraform/config/clouds.json."
  default     = ""
}

variable "gcp_region" {
  type        = string
  description = "Fallback GCP region. The canonical region profile lives in terraform/config/general.json."
  default     = "europe-central2"
}

variable "aws_region" {
  type        = string
  description = "Fallback AWS region. The canonical region profile lives in terraform/config/general.json."
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
  description = "Fallback Cloudflare Zone ID. The canonical non-secret value lives in terraform/config/dns.json."
  default     = ""
}

variable "app_domain" {
  type        = string
  description = "Fallback root domain. The canonical non-secret value lives in terraform/config/deploy.json."
  default     = "coinops.test"
}

variable "ssh_public_key_path" {
  type        = string
  description = "Path to SSH public key used for all cloud instances (GCP metadata ssh-keys, AWS key pair)."
  default     = "~/.ssh/ssh-key-coin-ops.pub"
}

variable "db_password" {
  description = "Password for the managed PostgreSQL database user"
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
  description = "When true, seed/update enabled cloud secret managers from local bootstrap secrets input."
  type        = bool
  default     = false
}
