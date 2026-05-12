variable "secrets" {
  type = map(object({
    secret_id = string
  }))
}

variable "secret_access" {
  type = map(object({
    service_account = string
    secrets         = list(string)
  }))
  default = {}
}

variable "service_accounts" {
  type = map(object({
    email = string
  }))
  default = {}
}
