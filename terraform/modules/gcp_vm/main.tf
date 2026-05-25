# GCP VM module — creates compute instances for all VMs with cloud: "gcp".
# Uses templatefile() for startup script to guarantee LF line endings (Windows-safe).

resource "google_compute_instance" "vm" {
  for_each = (var.config.general.cloud == "gcp" || var.config.general.cloud == "hybrid") ? {
    for name, vm in var.config.vms : name => vm
    if lookup(vm, "cloud", "gcp") == "gcp"
  } : {}

  name         = each.key
  machine_type = var.config.sizes[each.value.size].gcp
  zone         = var.config.locations[var.config.general.location].gcp.zones[each.value.zone]
  tags         = each.value.tags

  boot_disk {
    initialize_params {
      image = var.config.images.ubuntu_2404.gcp
      size  = try(each.value.disk_size, var.config.general.disk_size)
    }
  }

  network_interface {
    subnetwork = var.subnetwork

    dynamic "access_config" {
      for_each = each.value.public_ip ? [1] : []
      content {}
    }
  }

  metadata = {
    ssh-keys       = "${var.config.general.ops_user}:${var.ssh_public_key}"
    enable-oslogin = "false"
  }

  metadata_startup_script = templatefile("${path.module}/startup.sh", {
    ops_user = var.config.general.ops_user
    ssh_port = var.config.general.ssh_port
  })
}