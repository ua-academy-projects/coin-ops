resource "aws_instance" "this" {
  ami                         = var.ami_id
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = var.security_group_ids
  key_name                    = var.key_name
  associate_public_ip_address = var.assign_public_ip

  root_block_device {
    volume_size = var.disk_size_gb
    volume_type = var.disk_type
    encrypted   = true
  }

  user_data = <<-EOF
    #!/bin/bash
    set -e

    sed -i "s/^#*Port .*/Port ${var.ssh_port}/" /etc/ssh/sshd_config
    sed -i "s/^#*PermitRootLogin .*/PermitRootLogin no/" /etc/ssh/sshd_config
    sed -i "s/^#*PasswordAuthentication .*/PasswordAuthentication no/" /etc/ssh/sshd_config
    systemctl restart sshd || systemctl restart ssh
  EOF

  tags = merge(
    {
      Name        = var.name
      Environment = var.environment
      ManagedBy   = "terraform"
      SshUser     = var.ssh_user
    },
    var.tags
  )
}
