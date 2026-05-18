variable "db_secret_name" {
  type        = string
  description = "Name of the Secrets Manager secret storing database/runtime queue credentials."
  default     = "coinops-db-secrets"
}

variable "app_secret_name" {
  type        = string
  description = "Name of the Secrets Manager secret storing app/runtime integration credentials."
  default     = "coinops-app-secrets"
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "rabbitmq_password" {
  type      = string
  sensitive = true
}

variable "ghcr_token" {
  type      = string
  sensitive = true
}

variable "cloudflare_api_token" {
  type      = string
  sensitive = true
}

variable "tailscale_auth_key" {
  type      = string
  sensitive = true
}
