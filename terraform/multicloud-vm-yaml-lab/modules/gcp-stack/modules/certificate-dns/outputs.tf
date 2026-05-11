output "ip_address" {
  value = google_compute_global_address.app.address
}

output "certificate_self_link" {
  value = try(google_compute_managed_ssl_certificate.app[0].self_link, null)
}
