# variables.tf — inputs the EKS module needs from the root module.
# vpc_id and subnet_ids come from the existing aws_network module —
# EKS does not create its own VPC, it reuses the same network used by
# everything else in this project (same pattern as aws_vm, aws_lb).

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "coinops-eks"
}

variable "kubernetes_version" {
  description = "Kubernetes version for the EKS control plane"
  type        = string
  default     = "1.31"
}

variable "vpc_id" {
  description = "VPC ID where the cluster and nodes will run"
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs for the EKS control plane and node group. EKS requires at least 2 subnets in different Availability Zones."
  type        = list(string)
}

variable "node_instance_type" {
  description = "EC2 instance type for worker nodes"
  type        = string
  default     = "t3.small"
}

variable "node_desired_size" {
  description = "Desired number of worker nodes"
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Minimum number of worker nodes"
  type        = number
  default     = 1
}

variable "node_max_size" {
  description = "Maximum number of worker nodes"
  type        = number
  default     = 3
}
