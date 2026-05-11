variable "name_prefix" {
  type = string
}

variable "runtime" {
  type = any
}

variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "network_self_link" {
  type = string
}

variable "private_subnet_self_links" {
  type = map(string)
}
