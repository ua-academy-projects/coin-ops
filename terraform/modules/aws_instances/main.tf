locals {
  fallback_sizes = {
    micro  = "t3.micro"
    small  = "t3.small"
    medium = "m7i-flex.large"
    large  = "c7i-flex.large"
  }
  sizes = length(var.instance_sizes) > 0 ? var.instance_sizes : local.fallback_sizes

  fallback = {
    instance_size    = "micro"
    disk_size        = 10
    subnet           = "internal"
    has_public_ip    = false
    role             = ""
    ami_filter       = "debian-12-amd64-20*"
    ami_owner        = "136693071363"
    can_ip_forward   = false
    startup_script   = ""
    user_init_script = ""
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

  # Pre-render startup scripts per instance.
  # user_init_script (from general) runs on every VM and handles user creation + SSH port.
  # startup_script (per-instance) contains cloud-specific init (e.g. NAT bootstrap for jump-host).
  # Both are combined into a single user_data string.
  instance_scripts = {
    for name, cfg in local.instances : name => join("\n\n", compact([
      cfg.user_init_script != "" ? templatefile("${path.root}/${cfg.user_init_script}", {
        username       = var.username
        ssh_public_key = var.ssh_public_key
        ssh_port       = var.ssh_port
      }) : "",
      cfg.startup_script != "" ? templatefile("${path.root}/${cfg.startup_script}", {
        private_subnet_cidr = var.private_subnet_cidr
      }) : "",
    ]))
  }
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

  ami                         = data.aws_ami.this.id
  instance_type               = local.sizes[each.value.instance_size]
  subnet_id                   = var.subnet_ids[each.value.subnet]
  vpc_security_group_ids      = each.value.role != "" ? [var.sg_ids[each.value.role]] : []
  key_name                    = length(aws_key_pair.deployer) > 0 ? aws_key_pair.deployer[0].key_name : null
  associate_public_ip_address = each.value.has_public_ip
  source_dest_check           = !each.value.can_ip_forward
  user_data                   = local.instance_scripts[each.key] != "" ? local.instance_scripts[each.key] : null

  root_block_device {
    volume_size = each.value.disk_size
  }

  # Tags for cloud-native Ansible inventory (aws_ec2 plugin groups by tags.Role).
  tags = {
    # "aws-" prefix ensures unique cross-cloud hostnames in Ansible inventory.
    # The aws_ec2 plugin uses tag:Name as hostname — "aws-app-1" won't collide with GCP "app-1".
    # This is a tag-only change: terraform apply updates tags in-place, no instance recreation.
    Name    = "aws-${each.key}"
    Role    = each.value.role != "" ? each.value.role : "unset"
    Project = var.project_name
    Cloud   = "aws"
  }

  lifecycle {
    ignore_changes = [ami]
  }
}
