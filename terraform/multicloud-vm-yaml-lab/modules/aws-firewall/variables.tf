variable "name_prefix" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "ssh_source_ranges" {
  type = list(string)
}

variable "allow_icmp_from_bastion" {
  type = bool
}