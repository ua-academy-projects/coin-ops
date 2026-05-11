variable "name_prefix" {
  type = string
}

variable "network_self_link" {
  type = string
}

variable "firewall" {
  type = any
}

variable "app_port" {
  type = number
}

variable "bastion_target_tags" {
  type = list(string)
}

variable "app_target_tags" {
  type = list(string)
}

variable "db_target_tags" {
  type = list(string)
}

variable "allow_icmp_from_bastion" {
  type = bool
}
