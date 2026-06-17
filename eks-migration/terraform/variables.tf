variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "eks_cluster_version" {
  description = "EKS Cluster Version"
  type        = string
  default     = "1.30"
}
