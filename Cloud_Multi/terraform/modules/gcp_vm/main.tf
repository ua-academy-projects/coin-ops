resource "google_compute_instance" "vm" {
  for_each = var.cloud == "gcp" ? var.vms : {}

  name         = each.key
  machine_type = var.sizes[each.value.size].gcp
  zone         = var.zone
  tags         = each.value.tags

  boot_disk {
    initialize_params {
      image = var.image
      size  = try(each.value.disk_size, var.default_disk)
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
    ssh-keys = "${var.ops_user}:${var.ssh_public_key}"
  }

  metadata_startup_script = <<-EOT
    #!/bin/bash
    if [ -f /etc/ssh/sshd_config.d/custom-port.conf ]; then
      exit 0
    fi
    cloud-init status --wait
    systemctl disable --now ssh.socket
    echo "Port ${var.ssh_port}" > /etc/ssh/sshd_config.d/custom-port.conf
    systemctl enable ssh.service
    systemctl restart ssh.service
  EOT
}