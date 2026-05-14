locals {
  cloud                    = lower(var.cloud)
  gcp_enabled              = local.cloud == "gcp"
  aws_enabled              = local.cloud == "aws"
  bastion_jump_only_script = <<-SCRIPT
    #!/bin/sh
    set -eu

    mkdir -p /etc/ssh/sshd_config.d
    cat >/etc/ssh/sshd_config.d/99-jump-host-only.conf <<'EOF'
    # Managed by Terraform. Bastion is a jump host only.
    Match all
      AllowTcpForwarding yes
      PermitTTY no
      X11Forwarding no
      PermitTunnel no
    EOF

    sshd -t
    systemctl restart ssh || systemctl restart sshd || service ssh restart || service sshd restart
  SCRIPT
}

resource "google_compute_instance" "vm" {
  count        = local.gcp_enabled ? 1 : 0
  name         = var.name
  machine_type = var.vm.machine_type.gcp
  zone         = var.config.project.gcp.zone
  tags         = var.vm.tags

  boot_disk {
    initialize_params {
      image = var.vm.image.gcp
    }
  }

  network_interface {
    subnetwork = var.gcp_subnet_id
    network_ip = var.vm.ip

    dynamic "access_config" {
      for_each = var.vm.external_ip ? [1] : []
      content {}
    }
  }

  metadata = {
    ssh-keys = var.ssh_key
  }

  metadata_startup_script = var.vm.role == "bastion" ? local.bastion_jump_only_script : null
}

resource "aws_instance" "vm" {
  count                       = local.aws_enabled ? 1 : 0
  ami                         = var.vm.image.aws
  instance_type               = var.vm.machine_type.aws
  subnet_id                   = var.vm.role == "bastion" ? var.aws_public_subnet_id : var.aws_private_subnet_id
  private_ip                  = var.vm.ip
  key_name                    = var.aws_key_name
  vpc_security_group_ids      = var.vm.role == "bastion" ? [var.aws_bastion_security_group_id] : [var.aws_private_security_group_id]
  associate_public_ip_address = var.vm.external_ip
  user_data                   = var.vm.role == "bastion" ? local.bastion_jump_only_script : null
  user_data_replace_on_change = var.vm.role == "bastion"

  tags = {
    Name = var.name
  }
}
