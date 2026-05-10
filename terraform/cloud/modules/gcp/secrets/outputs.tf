output "secret_ids" {
  value = {
    for key, secret in google_secret_manager_secret.this : key => secret.secret_id
  }
}

output "secret_resource_ids" {
  value = {
    for key, secret in google_secret_manager_secret.this : key => secret.id
  }
}
