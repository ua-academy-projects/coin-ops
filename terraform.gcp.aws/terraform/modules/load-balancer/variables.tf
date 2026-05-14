variable "cloud" {
  description = "Selected cloud provider: gcp or aws."
  type        = string
}

variable "name" {
  description = "Base name for load balancer resources."
  type        = string
}

variable "port" {
  description = "Load balancer listener and backend port."
  type        = number
}

variable "gcp_region" {
  description = "GCP region. Required only for GCP."
  type        = string
  default     = null
}

variable "gcp_target_self_link" {
  description = "GCP target instance self link. Required only for GCP."
  type        = string
  default     = null
}

variable "aws_public_subnet_ids" {
  description = "AWS public subnet IDs. Required only for AWS."
  type        = list(string)
  default     = null
}

variable "aws_security_group_id" {
  description = "AWS load balancer security group ID. Required only for AWS."
  type        = string
  default     = null
}

variable "aws_target_instance_id" {
  description = "AWS target instance ID. Required only for AWS."
  type        = string
  default     = null
}
