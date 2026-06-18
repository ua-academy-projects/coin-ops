variable "jenkins" {
  type = object({
    namespace                  = string
    release_name               = string
    chart_repository           = string
    chart_name                 = string
    service_type               = string
    admin_secret_name          = string
    admin_username             = string
    admin_password_placeholder = string
  })
}
