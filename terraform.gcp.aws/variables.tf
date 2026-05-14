variable "cloud" {
  type        = string
  description = "Target cloud provider: gcp or aws"
  default     = "aws"

  validation {
    condition     = contains(["gcp", "aws"], lower(var.cloud))
    error_message = "cloud must be either gcp or aws."
  }
}

variable "inventory_output_path" {
  type        = string
  description = "Where Terraform should write the generated Ansible inventory."
  default     = "../ansible/inventory.generated"
}
variable "db_password" {
  description = "Password for AWS RDS PostgreSQL."
  type        = string
  sensitive   = true
}

variable "cloudflare_zone_name" {
  type        = string
  description = "Cloudflare zone name, for example smolyakov-devops.pp.ua. Leave empty to disable DNS automation."
  default     = ""
}

variable "cloudflare_account_id" {
  type        = string
  description = "Optional Cloudflare account ID for disambiguating the zone lookup."
  default     = ""
}

variable "cloudflare_record_name" {
  type        = string
  description = "Cloudflare DNS record name inside the zone."
  default     = "app"
}

variable "cloudflare_proxied" {
  type        = bool
  description = "Whether the Cloudflare record should be proxied."
  default     = true
}
