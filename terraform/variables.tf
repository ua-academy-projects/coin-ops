variable "gcp_credentials_file" {
  type      = string
  sensitive = true
  default   = ""
}

variable "aws_access_key" {
  type      = string
  sensitive = true
}

variable "aws_secret_key" {
  type      = string
  sensitive = true
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "azure_subscription_id" {
  type      = string
  sensitive = false
  default   = ""
}
variable "azure_client_id" {
  type      = string
  sensitive = true
  default   = ""
}
variable "azure_client_secret" {
  type      = string
  sensitive = true
  default   = ""
}
variable "azure_tenant_id" {
  type      = string
  sensitive = false
  default   = ""
}