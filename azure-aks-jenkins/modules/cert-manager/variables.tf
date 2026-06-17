variable "namespace" {
  type        = string
  description = "Namespace where cert-manager will be installed."
  default     = "cert-manager"
}

variable "release_name" {
  type        = string
  description = "Helm release name for cert-manager."
  default     = "cert-manager"
}

variable "chart_version" {
  type        = string
  description = "Version of the cert-manager Helm chart."
  default     = "v1.18.1"
}

variable "cluster_issuer_name" {
  type        = string
  description = "ClusterIssuer name for Let's Encrypt."
  default     = "letsencrypt-prod"
}

variable "letsencrypt_email" {
  type        = string
  description = "Email used for Let's Encrypt ACME registration."
}

variable "acme_server" {
  type        = string
  description = "ACME directory URL."
  default     = "https://acme-v02.api.letsencrypt.org/directory"
}

variable "ingress_class_name" {
  type        = string
  description = "Ingress class used for HTTP-01 challenges."
  default     = "traefik"
}
