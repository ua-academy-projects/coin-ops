locals {
  fallback_sizes = {
    small  = "e2-micro"
    medium = "e2-standard-2"
    large  = "e2-standard-4"
  }
  sizes = length(var.instance_sizes) > 0 ? var.instance_sizes : local.fallback_sizes

  fallback = {
    instance_size = "small"
    os_image      = "debian-cloud/debian-12"
    disk_size     = 10
    zone          = "europe-central2-a"
    subnet        = "internal"
    has_public_ip = false
    role          = ""
  }

  # якщо config.json відсутній або порожній — створюємо мінімальний інстанс
  fallback_instances = {
    "default-vm" = {}
  }
  source_instances = length(var.instances) > 0 ? var.instances : local.fallback_instances

  instances = {
    for name, cfg in local.source_instances : name => merge(
      local.fallback,
      var.defaults,
      var.cloud_defaults,
      cfg
    )
  }
}

resource "google_compute_instance" "vm" {
  for_each = local.instances

  name         = each.key
  machine_type = local.sizes[each.value.instance_size]
  zone         = each.value.zone
  tags         = each.value.role != "" ? [each.value.role] : []

  boot_disk {
    initialize_params {
      image = each.value.os_image
      size  = each.value.disk_size
    }
  }

  network_interface {
    network    = var.network_id
    subnetwork = var.subnet_ids[each.value.subnet]

    dynamic "access_config" {
      for_each = each.value.has_public_ip ? [1] : []
      content {}
    }
  }
}
