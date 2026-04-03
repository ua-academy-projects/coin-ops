variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "eu-central-1"
}

variable "ami_id" {
  description = "Ubuntu 24.04 LTS AMI ID (region-specific — check AWS console)"
  type        = string
  # eu-central-1 Ubuntu 24.04: ami-0faab6bdbac9486fb (verify before use)
}

variable "instance_type" {
  description = "EC2 instance type for all nodes"
  type        = string
  default     = "t3.micro"
}

variable "key_pair_name" {
  description = "Name of the AWS key pair to use for SSH access"
  type        = string
}

variable "your_ip" {
  description = "Your public IP in CIDR notation for SSH access (e.g. 1.2.3.4/32)"
  type        = string
}
