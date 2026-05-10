# main.tf

resource "aws_instance" "this" {
  for_each = local.instances

  ami                         = each.value.ami
  instance_type               = each.value.instance_type
  availability_zone           = each.value.availability_zone
  subnet_id                   = each.value.subnet_id
  associate_public_ip_address = each.value.public_ip
  vpc_security_group_ids      = lookup(var.security_group_ids, each.key, null) != null ? [var.security_group_ids[each.key]] : null

  root_block_device {
    volume_size = each.value.disk_size_gb
  }

  tags = merge(
    { for tag in each.value.tags : tag => "true" },
    {
      Name = each.key
    }
  )
}
