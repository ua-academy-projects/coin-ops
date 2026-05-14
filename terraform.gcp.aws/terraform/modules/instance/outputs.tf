output "external_ip" {
  value = try(google_compute_instance.vm[0].network_interface[0].access_config[0].nat_ip, aws_instance.vm[0].public_ip, null)
}

output "internal_ip" {
  value = try(google_compute_instance.vm[0].network_interface[0].network_ip, aws_instance.vm[0].private_ip, null)
}

output "id" {
  value = try(google_compute_instance.vm[0].id, aws_instance.vm[0].id, null)
}

output "self_link" {
  value = try(google_compute_instance.vm[0].self_link, null)
}
