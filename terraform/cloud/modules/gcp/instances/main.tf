resource "google_compute_instance" "this" {
  for_each = local.instances

  name                      = each.key
  machine_type              = each.value.machine_type
  zone                      = each.value.zone
  tags                      = each.value.tags
  can_ip_forward            = each.value.can_ip_forward
  allow_stopping_for_update = true

  boot_disk {
    initialize_params {
      image = each.value.image
      size  = each.value.disk_size_gb
    }
  }

  network_interface {
    network    = var.network_name
    subnetwork = each.value.subnetwork

    dynamic "access_config" {
      for_each = each.value.assign_public_ip ? [1] : []
      content {}
    }
  }

  metadata = {
    ssh-keys               = "${var.ssh_user}:${trimspace(file(each.value.ssh_public_key_path))}"
    block-project-ssh-keys = "TRUE"
  }

  dynamic "service_account" {
    for_each = each.value.service_account_email != null ? [1] : []

    content {
      email  = each.value.service_account_email
      scopes = ["https://www.googleapis.com/auth/cloud-platform"]
    }
  }
}
