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

variable "app_url" {
  type = string
}

variable "app_domain" {
  type = string
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