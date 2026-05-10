variable "secrets" {
  type = map(object({
    secret_id = string
  }))
}
