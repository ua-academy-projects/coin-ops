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

variable "tailscale_auth_key" {
  type      = string
  sensitive = true
  default   = ""
}

variable "ssh_public_key_path" {
  type        = string
  description = "Path to SSH public key file"
  default     = "/d/.ssh/id_ed25519_devops.pub"
}
variable "alert_email" {
  type        = string
  description = "Email address for CloudWatch alarm notifications"
  default     = "marta.penina.academic@gmail.com"
}

variable "aws_account_id" {
  type        = string
  description = "AWS account ID for S3 bucket policy"
  default     = "584856877361"
}
