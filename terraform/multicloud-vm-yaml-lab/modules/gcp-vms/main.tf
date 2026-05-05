locals {
  instance_defaults = merge(
    {
      zone       = var.zone
      network    = var.network
      subnetwork = var.subnetwork
      private_ip = null
      public_ip  = false
      nat_ip     = null
      tags       = []
    },
    var.defaults
  )

  instances = {
    for name, instance in var.instances :
    name => merge(local.instance_defaults, instance)
  }
}

resource "google_compute_instance" "this" {
  for_each = local.instances

  name         = each.key
  zone         = each.value.zone
  machine_type = each.value.machine_type
  tags         = each.value.tags

  boot_disk {
    initialize_params {
      image = each.value.image
      size  = each.value.disk_size_gb
    }
  }

  network_interface {
    network    = each.value.network
    subnetwork = each.value.subnetwork
    network_ip = each.value.private_ip

    dynamic "access_config" {
      for_each = each.value.public_ip ? [1] : []
      content {
        nat_ip = each.value.nat_ip
      }
    }
  }

  metadata = {
    ssh-keys               = "${each.value.ssh_user}:${trimspace(file(pathexpand(each.value.ssh_public_key_path)))}"
    block-project-ssh-keys = "true"
    enable-oslogin         = "FALSE"
  }
}
