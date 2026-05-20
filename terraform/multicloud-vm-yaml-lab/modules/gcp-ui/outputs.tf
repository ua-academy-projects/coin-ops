output "endpoint" {
  value = google_compute_address.ui.address
}

output "endpoint_type" {
  value = "A"
}

output "instances" {
  value = {
    ui = {
      name       = local.name
      role       = "ui"
      private_ip = google_compute_instance.ui.network_interface[0].network_ip
      public_ip  = google_compute_address.ui.address
    }
  }
}

output "ssh_config" {
  value = local.ssh_config
}

output "ansible_inventory" {
  value = local.ansible_inventory
}
