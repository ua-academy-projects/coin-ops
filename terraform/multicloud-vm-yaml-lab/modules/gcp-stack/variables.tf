variable "stack" {
  type = any
}


variable "db_password" {
  type      = string
  sensitive = true
  default   = null
}
