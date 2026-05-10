variable "secret_access" {
  type = map(object({
    service_account = string
    secrets         = list(string)
  }))
}

variable "service_accounts" {
  type = map(object({
    email = string
  }))
}

variable "secrets" {
  type = map(string)
}
