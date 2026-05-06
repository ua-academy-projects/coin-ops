locals {
  fallback_sizes = {
    micro = "t3.micro"
    small = "t3.small"
    medium = "m7i-flex.large"
    large = "c7i-flex.large"
  }
  sizes = length(var.instance_sizes) > 0 ? var.instance_sizes : local.fallback_sizes

  fallback = {
    instance_size  = "micro"
    disk_size      = 10
    subnet         = "internal"
    has_public_ip  = false
    role           = ""
    ami_filter     = "amzn2-ami-hvm-*-x86_64-gp2"
    ami_owner      = "amazon"
    can_ip_forward = false
    startup_script = ""
  }

  # If config.json is empty or missing, create a minimal fallback instance.
  fallback_instances = { "default-vm" = {} }
  source_instances = jsondecode(
    length(var.instances) > 0
      ? jsonencode(var.instances)
      : jsonencode(local.fallback_instances)
  )

  instances = {
    for name, cfg in local.source_instances : name => merge(
      local.fallback,
      var.defaults,
      var.cloud_defaults,
      cfg
    )
  }

  ami_filter = lookup(var.cloud_defaults, "ami_filter", local.fallback.ami_filter)
  ami_owner  = lookup(var.cloud_defaults, "ami_owner", local.fallback.ami_owner)
}

data "aws_ami" "this" {
  most_recent = true
  owners      = [local.ami_owner]

  filter {
    name   = "name"
    values = [local.ami_filter]
  }
}

resource "aws_key_pair" "deployer" {
  count      = var.ssh_public_key != "" ? 1 : 0
  key_name   = "terraform-aws-key"
  public_key = var.ssh_public_key
}

resource "aws_instance" "vm" {
  for_each = local.instances

  ami                    = data.aws_ami.this.id
  instance_type          = local.sizes[each.value.instance_size]
  subnet_id              = var.subnet_ids[each.value.subnet]
  vpc_security_group_ids = each.value.role != "" ? [var.sg_ids[each.value.role]] : []
  key_name               = length(aws_key_pair.deployer) > 0 ? aws_key_pair.deployer[0].key_name : null
  associate_public_ip_address = each.value.has_public_ip
  source_dest_check           = !each.value.can_ip_forward
  user_data                   = each.value.startup_script != "" ? file("${path.root}/${each.value.startup_script}") : null

  root_block_device {
    volume_size = each.value.disk_size
  }

  tags = { Name = each.key }

  lifecycle {
    ignore_changes = [ami]
  }
}
