variable "cluster_name" {
  description = "EKS cluster name, used for tagging"
  type        = string
}

variable "oidc_issuer_url" {
  description = "The OIDC issuer URL from the EKS cluster (cluster.identity[0].oidc[0].issuer)"
  type        = string
}

