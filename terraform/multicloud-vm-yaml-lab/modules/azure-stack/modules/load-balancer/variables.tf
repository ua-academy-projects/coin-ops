variable "name_prefix" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "app_instances" {
  type = map(any)
}

variable "gateway_subnet_id" {
  type = string
}

variable "app_port" {
  type = number
}

variable "health_path" {
  type = string
}

variable "api_domain" {
  type    = string
  default = ""
}

variable "gateway_identity_id" {
  type = string
}

variable "ssl_certificate_key_vault_secret_id" {
  type = string
}
