variable "cloud" {
  description = "Selected cloud provider: gcp or aws."
  type        = string
}

variable "network_name" {
  description = "Network name."
  type        = string
}

variable "vpc_id" {
  description = "AWS VPC ID. Required only for AWS."
  type        = string
  default     = null
}

variable "allowed_source_cidr" {
  description = "Public CIDR allowed to SSH to bastion."
  type        = string
}

variable "bastion_tags" {
  description = "Bastion tags. Required only for GCP firewall targeting."
  type        = list(string)
  default     = []
}

variable "private_target_tags" {
  description = "Private VM target tags. Required only for GCP firewall targeting."
  type        = list(string)
  default     = []
}

variable "web_target_tags" {
  description = "Web VM target tags. Required only for GCP load balancer traffic."
  type        = list(string)
  default     = []
}


variable "private_service_cidr" {
  description = "Private subnet CIDR allowed for east-west service traffic in AWS."
  type        = string
  default     = null
}

variable "load_balancer_port" {
  description = "Load balancer listener and backend port."
  type        = number
  default     = 80
}
