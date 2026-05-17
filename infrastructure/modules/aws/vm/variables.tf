variable "name" {
  description = "EC2 instance name"
  type        = string
}

variable "environment" {
  description = "Environment tag"
  type        = string
  default     = "learning"
}

variable "ssh_user" {
  description = "SSH username for the selected AMI"
  type        = string
}

variable "ssh_port" {
  description = "SSH port to configure on the instance"
  type        = number
  default     = 47832
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
}

variable "ami_id" {
  description = "AMI ID"
  type        = string
}

variable "disk_size_gb" {
  description = "Root volume size in GB"
  type        = number
  default     = 10
}

variable "disk_type" {
  description = "Root volume type"
  type        = string
  default     = "gp3"
}

variable "subnet_id" {
  description = "Subnet ID"
  type        = string
}

variable "security_group_ids" {
  description = "Security group IDs"
  type        = list(string)
  default     = []
}

variable "key_name" {
  description = "AWS key pair name"
  type        = string
}

variable "assign_public_ip" {
  description = "Whether to assign a public IP"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags to apply to the instance"
  type        = map(string)
  default     = {}
}
