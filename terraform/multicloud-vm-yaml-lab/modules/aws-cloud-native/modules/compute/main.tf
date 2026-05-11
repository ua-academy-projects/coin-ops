locals {
  app_instances = { for name, inst in var.instances : name => inst if contains(var.app_names, name) }
  db_instances  = var.create_db_instance ? { for name, inst in var.instances : name => inst if name == var.db_name } : {}
  bastions      = { for name, inst in var.instances : name => inst if name == var.bastion_name }

  user_data = <<-EOT
  #cloud-config
  users:
    - name: ${var.ssh.user}
      groups: [sudo]
      shell: /bin/bash
      sudo: ['ALL=(ALL) NOPASSWD:ALL']
      ssh_authorized_keys:
        - ${var.ssh_public_key}
  package_update: true
  packages:
    - python3
  EOT
}

data "aws_ami" "selected" {
  for_each = { for image_key, image_config in var.image_catalog : image_key => image_config.aws }

  most_recent = true
  owners      = each.value.owners

  filter {
    name   = "name"
    values = [each.value.name_filter]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_key_pair" "lab" {
  key_name   = "${var.name_prefix}-key"
  public_key = var.ssh_public_key
}

resource "aws_instance" "bastion" {
  for_each = local.bastions

  ami                         = data.aws_ami.selected[each.value.image_key].id
  instance_type               = each.value.aws_instance_type
  subnet_id                   = var.public_subnet_ids["0"]
  private_ip                  = each.value.private_ip
  associate_public_ip_address = true
  vpc_security_group_ids      = [var.security_groups.bastion]
  key_name                    = aws_key_pair.lab.key_name
  user_data                   = local.user_data

  root_block_device {
    volume_size = each.value.disk_size_gb
    volume_type = "gp3"
  }

  tags = {
    Name = each.value.name
    Role = "bastion"
  }
}

resource "aws_instance" "app" {
  for_each = local.app_instances

  ami                         = data.aws_ami.selected[each.value.image_key].id
  instance_type               = each.value.aws_instance_type
  subnet_id                   = var.private_subnet_ids[tostring(index(var.app_names, each.key) % length(var.private_subnet_ids))]
  private_ip                  = each.value.private_ip
  associate_public_ip_address = false
  vpc_security_group_ids      = [var.security_groups.app]
  key_name                    = aws_key_pair.lab.key_name
  iam_instance_profile        = var.app_iam_instance_profile_name
  user_data                   = local.user_data

  root_block_device {
    volume_size = each.value.disk_size_gb
    volume_type = "gp3"
  }

  tags = {
    Name = each.value.name
    Role = "app"
  }
}

resource "aws_instance" "db" {
  for_each = local.db_instances

  ami                         = data.aws_ami.selected[each.value.image_key].id
  instance_type               = each.value.aws_instance_type
  subnet_id                   = var.private_subnet_ids["0"]
  private_ip                  = each.value.private_ip
  associate_public_ip_address = false
  vpc_security_group_ids      = [var.security_groups.db]
  key_name                    = aws_key_pair.lab.key_name
  user_data                   = local.user_data

  root_block_device {
    volume_size = each.value.disk_size_gb
    volume_type = "gp3"
  }

  tags = {
    Name = each.value.name
    Role = "db"
  }
}
