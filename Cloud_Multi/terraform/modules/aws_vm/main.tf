resource "aws_key_pair" "main" {
  count = var.cloud == "aws" ? 1 : 0

  key_name   = "marta-ops-key"
  public_key = var.ssh_public_key
}

resource "aws_instance" "vm" {
  for_each = var.cloud == "aws" ? var.vms : {}

  ami                         = var.ami
  instance_type               = var.sizes[each.value.size].aws
  subnet_id                   = each.value.public_ip ? var.public_subnet_id : var.private_subnet_id
  associate_public_ip_address = each.value.public_ip
  vpc_security_group_ids      = each.value.public_ip ? [var.jump_host_sg_id] : [var.internal_sg_id]
  key_name                    = aws_key_pair.main[0].key_name

  root_block_device {
    volume_size = try(each.value.disk_size, var.default_disk)
  }

  user_data = <<-EOT
    #!/bin/bash
    if [ -f /etc/ssh/sshd_config.d/custom-port.conf ]; then
      exit 0
    fi

    useradd -m -s /bin/bash ${var.ops_user}
    mkdir -p /home/${var.ops_user}/.ssh
    cp /home/ubuntu/.ssh/authorized_keys /home/${var.ops_user}/.ssh/authorized_keys
    chown -R ${var.ops_user}:${var.ops_user} /home/${var.ops_user}/.ssh
    chmod 700 /home/${var.ops_user}/.ssh
    chmod 600 /home/${var.ops_user}/.ssh/authorized_keys
    echo "${var.ops_user} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${var.ops_user}

    systemctl disable --now ssh.socket
    echo "Port ${var.ssh_port}" > /etc/ssh/sshd_config.d/custom-port.conf
    systemctl enable ssh.service
    systemctl restart ssh.service
  EOT

  tags = {
    Name = each.key
  }
}