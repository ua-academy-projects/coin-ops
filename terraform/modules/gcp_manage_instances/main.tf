locals {
  fallback = {
    zone            = "europe-central2-a"
    machine_type    = "e2-micro"
    os_image        = "debian-cloud/debian-12"
    disk_size       = 10
    vpc_name        = "default"
    subnet_name     = "default"
    has_external_ip = false
    tags            = []
  }
  instances = {
    for name, cfg in var.instances : name => merge(local.fallback, var.defaults, cfg)
  }
}

resource "google_compute_instance" "vm" {
  for_each = local.instances

  name         = each.key
  machine_type = each.value.machine_type
  zone         = each.value.zone
  tags         = each.value.tags

  boot_disk {
    initialize_params {
      image = each.value.os_image
      size  = each.value.disk_size
    }
  }

  network_interface {
    network    = each.value.vpc_name
    subnetwork = each.value.subnet_name

    dynamic "access_config" {
      for_each = each.value.has_external_ip ? [1] : []
      content {}
    }
  }
}
