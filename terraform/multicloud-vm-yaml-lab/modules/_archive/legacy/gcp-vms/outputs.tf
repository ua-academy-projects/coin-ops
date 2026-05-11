output "instances" {
  value = {
    for name, instance in google_compute_instance.this :
    name => {
      name        = instance.name
      internal_ip = instance.network_interface[0].network_ip
      external_ip = try(instance.network_interface[0].access_config[0].nat_ip, null)
    }
  }
}
