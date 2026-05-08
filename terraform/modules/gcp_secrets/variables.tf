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
