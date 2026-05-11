output "refs" {
  value = {
    for key, secret in google_secret_manager_secret.this : key => {
      provider  = "gcp"
      name      = secret.secret_id
      arn       = ""
      secret_id = secret.secret_id
      id        = secret.id
    }
  }
}
