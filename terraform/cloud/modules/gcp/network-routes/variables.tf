variable "network_name" {
  type = string
}

variable "route_name" {
  type = string
}

variable "destination_range" {
  type = string
}

variable "target_tags" {
  type = list(string)
}

variable "next_hop_instance" {
  type = string
}
