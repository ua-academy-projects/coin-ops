variable "secrets" {
  type = map(object({
    secret_id = string
  }))
}

variable "workloads" {
  type = map(object({
    identity = optional(string)
    secrets  = optional(list(string))
  }))
}

variable "service_accounts" {
  type = map(object({
    email = string
  }))
  default = {}
}
