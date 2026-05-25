variable "cloud_provider" {
  description = "Target cloud platform: 'gcp', 'aws', or 'azure'"
  type        = string
  validation {
    condition     = contains(["gcp", "aws", "azure"], var.cloud_provider)
    error_message = "cloud_provider must be 'gcp', 'aws', or 'azure'."
  }
}

variable "environment" {
  description = "Environment configuration to use (e.g., 'dev', 'staging', 'prod', or 'default')"
  type        = string
  default     = "default"
}

variable "gcp_project_id" {
  description = "GCP Project ID"
  type        = string
  default     = ""
}

variable "state_bucket" {
  description = "Name of the GCS/S3 bucket for Terraform state"
  type        = string
  default     = ""
}

variable "ssh_user" {
  description = "SSH username"
  type        = string
  default     = "ubuntu"
}

variable "public_key_path" {
  description = "Path to SSH public key file"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}



variable "use_packer_image" {
  description = "Whether to use Packer-built images instead of base images"
  type        = bool
  default     = false
}

variable "rabbitmq_password" {
  description = "RabbitMQ password"
  type        = string
  sensitive   = true
}