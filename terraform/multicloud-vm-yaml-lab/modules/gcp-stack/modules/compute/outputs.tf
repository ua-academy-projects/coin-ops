locals {
  instance_outputs = {
    for name, instance in google_compute_instance.this : name => {
      name       = var.instances[name].name
      role       = var.instances[name].role
      private_ip = instance.network_interface[0].network_ip
      public_ip  = try(instance.network_interface[0].access_config[0].nat_ip, "")
    }
  }

  app_instance_outputs = {
    for name, instance in google_compute_instance.this : name => merge(local.instance_outputs[name], {
      id        = instance.id
      self_link = instance.self_link
      zone      = instance.zone
    }) if var.instances[name].role == "app"
  }
}

output "instances" {
  value = local.instance_outputs
}

output "app_instances" {
  value = local.app_instance_outputs
}
