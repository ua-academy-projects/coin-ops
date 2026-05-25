variable "cloud" {
  type = string
}

variable "name_prefix" {
  type = string
}

variable "ssh" {
  type = any
}

variable "instances" {
  type = map(any)
}

variable "bastion_name" {
  type = string
}

variable "app_names" {
  type = list(string)
}

variable "db_name" {
  type = string
}

variable "k3s_names" {
  type    = list(string)
  default = []
}

variable "bastion_advertise_routes" {
  type    = list(string)
  default = []
}

variable "app_url" {
  type = string
}

# Shared app-tier config from config/lab.yaml (app.image_registry/app.image_tag),
# emitted as coinops_* so Ansible reads them (with an env override).
variable "image_registry" {
  type    = string
  default = ""
}

variable "image_tag" {
  type    = string
  default = ""
}

# k3s ingress base domain from config/lab.yaml (domain.k3s_ingress); emitted as
# coinops_k3s_ingress_domain so the k3s roles build <app>.<domain> from one source.
variable "k3s_ingress_domain" {
  type    = string
  default = ""
}

variable "app_domain" {
  type = string
}

variable "api_url" {
  type    = string
  default = ""
}

variable "ui_proxy_url" {
  type    = string
  default = ""
}

variable "ui_history_url" {
  type    = string
  default = ""
}

variable "cors_origin" {
  type    = string
  default = ""
}

variable "known_hosts_file" {
  type = string
}

variable "load_balancer" {
  type = any
}

variable "runtime" {
  type    = any
  default = {}
}

variable "secret_refs" {
  type    = any
  default = {}
}
