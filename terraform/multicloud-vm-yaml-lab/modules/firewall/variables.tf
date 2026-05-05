variable "name_prefix" {
  type = string
}

variable "network" {
  type = string
}

variable "ssh_source_ranges" {
  type = list(string)
}

variable "bastion_target_tags" {
  type = list(string)
}

variable "private_target_tags" {
  type = list(string)
}

variable "allow_icmp_from_bastion" {
  type    = bool
  default = false
}
