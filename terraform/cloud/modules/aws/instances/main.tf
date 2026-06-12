# aws/instances/main.tf

resource "aws_instance" "this" {
  for_each = local.instances

  ami                         = each.value.ami
  instance_type               = each.value.instance_type
  availability_zone           = each.value.availability_zone
  subnet_id                   = each.value.subnet_id
  associate_public_ip_address = each.value.public_ip
  vpc_security_group_ids      = lookup(var.security_group_ids, each.key, null) != null ? [var.security_group_ids[each.key]] : null
  iam_instance_profile        = each.value.iam_instance_profile
  source_dest_check           = !each.value.can_ip_forward
  user_data = templatefile("${path.module}/user_data.sh.tpl", {
    ssh_user       = var.ssh_user
    ssh_public_key = local.ssh_public_key
  })

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

resource "aws_iam_role_policy" "secret_access" {
  for_each = local.secret_access_bindings

  name = "${each.value.identity}-${each.value.secret_name}-secret-access"
  role = aws_iam_role.this[each.value.identity].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ]
      Resource = data.aws_secretsmanager_secret.this[each.value.secret_key].arn
    }]
  })
}
