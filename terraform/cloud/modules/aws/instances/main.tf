# main.tf

resource "aws_instance" "this" {
  for_each = local.instances

  ami                         = each.value.ami
  instance_type               = each.value.instance_type
  availability_zone           = each.value.availability_zone
  subnet_id                   = each.value.subnet_id
  associate_public_ip_address = each.value.public_ip
  vpc_security_group_ids      = lookup(var.security_group_ids, each.key, null) != null ? [var.security_group_ids[each.key]] : null
  iam_instance_profile        = each.value.iam_instance_profile

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

resource "aws_iam_role" "this" {
  for_each = local.workload_identities

  name = each.value.name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_instance_profile" "this" {
  for_each = local.workload_identities

  name = each.value.name
  role = aws_iam_role.this[each.key].name
}
