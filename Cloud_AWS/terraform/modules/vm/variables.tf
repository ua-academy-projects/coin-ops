variable "name" {
  description = "VM instance name"
  type        = string
}

variable "instance_type" {
  description = "AWS instance type (e.g., t2.micro)"
  type        = string
}

variable "ami" {
  description = "AMI ID for the instance"
  type        = string
}

variable "disk_size" {
  description = "Root volume size in GB"
  type        = number
  default     = 10
}

variable "tags" {
  description = "Tags for the instance"
  type        = list(string)
}

variable "subnet_id" {
  description = "Subnet ID to launch the instance in"
  type        = string
}

variable "vpc_security_group_ids" {
  description = "List of security group IDs"
  type        = list(string)
}

variable "public_ip" {
  description = "Whether to assign a public IP"
  type        = bool
  default     = false
}

variable "ssh_user" {
  description = "Operational user for SSH access"
  type        = string
}

variable "ssh_port" {
  description = "Custom SSH port"
  type        = string
}

variable "key_name" {
  description = "AWS key pair name for SSH"
  type        = string
}