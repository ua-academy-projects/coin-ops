variable "instances" {
  type = map(any)
}

variable "ssh" {
  type = any
}

variable "ssh_public_key" {
  type = string
}

variable "zones" {
  type = list(string)
}

variable "app_names" {
  type = list(string)
}

variable "db_name" {
  type = string
}

variable "bastion_name" {
  type = string
}

variable "network_self_link" {
  type = string
}

variable "public_subnet_self_links" {
  type = map(string)
}

variable "private_subnet_self_links" {
  type = map(string)
}


variable "app_service_account_email" {
  type    = string
  default = null
}
