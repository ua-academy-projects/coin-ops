# variables.tf


# network

variable "network_id" {
  type = string
}


# selectors

variable "workload_names" {
  type = list(string)
}


# rules

variable "rules" {
  type = map(object({
    description      = string
    direction        = string
    priority         = number
    protocol         = string
    ports            = list(string)
    cidr_blocks      = list(string)
    source_workloads = list(string)
    target_workloads = list(string)
  }))
}
