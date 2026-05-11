data "aws_ami" "selected" {
  for_each = var.image_catalog

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
  key_name   = "coinops-lab-key"
  public_key = file(var.ssh_public_key_path)
}

resource "aws_instance" "vm" {
  for_each = var.instances

  ami                         = data.aws_ami.selected[each.value.image_key].id
  instance_type               = each.value.instance_type
  subnet_id                   = var.subnet_id
  private_ip                  = each.value.private_ip
  associate_public_ip_address = each.value.public_ip
  key_name                    = aws_key_pair.lab.key_name
  availability_zone           = var.availability_zone

  vpc_security_group_ids = [
    each.value.role == "bastion"
    ? var.security_groups.bastion
    : var.security_groups.private
  ]

  root_block_device {
    volume_size = each.value.disk_size_gb
    volume_type = "gp3"
  }

  tags = {
    Name = each.value.name
    Role = each.value.role
  }
}