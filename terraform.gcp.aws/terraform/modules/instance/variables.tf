variable "cloud" {
  description = "Selected cloud provider: gcp or aws."
  type        = string
}

variable "config" {
  description = "Decoded infrastructure config."
  type        = any
}

variable "name" {
  description = "Instance name."
  type        = string
}

variable "vm" {
  description = "VM config object from config.yml."
  type        = any
}

variable "ssh_key" {
  description = "GCP SSH metadata value."
  type        = string
  default     = null
}

variable "gcp_subnet_id" {
  description = "GCP subnet ID. Required only for GCP."
  type        = string
  default     = null
}

variable "aws_public_subnet_id" {
  description = "AWS public subnet ID. Required only for AWS."
  type        = string
  default     = null
}

variable "aws_private_subnet_id" {
  description = "AWS private subnet ID. Required only for AWS."
  type        = string
  default     = null
}

variable "aws_key_name" {
  description = "AWS key pair name. Required only for AWS."
  type        = string
  default     = null
}

variable "aws_bastion_security_group_id" {
  description = "AWS bastion security group ID. Required only for AWS."
  type        = string
  default     = null
}

variable "aws_private_security_group_id" {
  description = "AWS private security group ID. Required only for AWS."
  type        = string
  default     = null
}
