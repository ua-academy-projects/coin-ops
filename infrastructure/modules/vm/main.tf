resource "google_compute_instance" "this" {
  name         = var.name
  machine_type = var.machine_type
  zone         = var.zone
  project      = var.project_id

  boot_disk {
    initialize_params {
      image = var.os_image
      size  = var.disk_size_gb
      type  = var.disk_type
    }
  }

  network_interface {
    network    = var.network_self_link
    subnetwork = var.subnet_self_link

    # Assign public IP only if requested
    dynamic "access_config" {
      for_each = var.assign_public_ip ? [1] : []
      content {}
    }
  }

  # ----------------------------------------------------------------------------
  # Startup script — runs once on first boot
  # Creates SSH user, configures SSH port, hardens SSH config
  # ----------------------------------------------------------------------------
  metadata = {
    enable-oslogin = "false"
    ssh-keys       = "${var.ssh_user}:${var.ssh_public_key}"
    startup-script = <<-EOF
      #!/bin/bash
      set -e

      # ---- Create SSH user ----
      if ! id "${var.ssh_user}" &>/dev/null; then
        useradd -m -s /bin/bash ${var.ssh_user}
        usermod -aG sudo ${var.ssh_user}
        echo "${var.ssh_user} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/${var.ssh_user}
        chmod 0440 /etc/sudoers.d/${var.ssh_user}
      fi

      # ---- Configure SSH ----
      sed -i "s/^#*Port .*/Port ${var.ssh_port}/" /etc/ssh/sshd_config
      sed -i "s/^#*PermitRootLogin .*/PermitRootLogin no/" /etc/ssh/sshd_config
      sed -i "s/^#*PasswordAuthentication .*/PasswordAuthentication no/" /etc/ssh/sshd_config
      sed -i "s/^#*X11Forwarding .*/X11Forwarding no/" /etc/ssh/sshd_config

      # ---- Restart SSH ----
      systemctl restart sshd

      echo "Bootstrap complete: SSH user ${var.ssh_user} configured on port ${var.ssh_port}"
    EOF
  }

  tags = var.tags

  labels = merge(
    {
      managed-by  = "terraform"
      environment = var.environment
    },
    var.labels
  )
}