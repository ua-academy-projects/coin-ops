variable "namespace" {
  type        = string
  description = "Namespace where Traefik will be installed."
}

variable "release_name" {
  type        = string
  description = "Helm release name for Traefik."
  default     = "traefik"
}

variable "chart_version" {
  type        = string
  description = "Version of the Traefik Helm chart."
  default     = "41.0.0"
}

variable "ingress_class_name" {
  type        = string
  description = "IngressClass name managed by Traefik."
  default     = "traefik"
}
