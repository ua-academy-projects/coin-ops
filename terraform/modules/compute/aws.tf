# ═════════════════════════════════════════════════════════════════════════════
# AWS EC2 INSTANCES
# ═════════════════════════════════════════════════════════════════════════════

# ── AMI lookup (Debian 12) ───────────────────────────────────────────────────
data "aws_ami" "default" {
  count = (var.cloud_provider == "aws" && !var.use_packer_image) ? 1 : 0

  most_recent = true
  owners      = ["136693071363"] # Debian

  filter {
    name   = "name"
    values = ["debian-12-amd64-*"]
  }
  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ── AMI lookup (Packer) ──────────────────────────────────────────────────────
data "aws_ami" "packer" {
  count = (var.cloud_provider == "aws" && var.use_packer_image) ? 1 : 0

  most_recent = true
  owners      = ["self"]

  filter {
    name   = "name"
    values = ["coinops-v1-*"]
  }
}

# ── SSH Key Pair ─────────────────────────────────────────────────────────────
resource "aws_key_pair" "this" {
  count = var.cloud_provider == "aws" && var.ssh_public_key != "" ? 1 : 0

  key_name   = "terraform-key"
  public_key = var.ssh_public_key
}

# ── EC2 Instances ────────────────────────────────────────────────────────────
resource "aws_instance" "this" {
  for_each = var.cloud_provider == "aws" ? local.resolved_vms : {}

  ami           = var.use_packer_image ? data.aws_ami.packer[0].id : data.aws_ami.default[0].id
  instance_type = each.value.instance_type
  subnet_id     = var.subnet_ids[each.value.subnet_name]
  private_ip    = each.value.private_ip

  associate_public_ip_address = each.value.public_ip

  key_name               = var.ssh_public_key != "" ? aws_key_pair.this[0].key_name : null
  vpc_security_group_ids = var.security_group_ids

  root_block_device {
    volume_size           = each.value.disk_size_gb
    volume_type           = each.value.disk_type
    delete_on_termination = true
  }

  user_data = each.value.startup_script != "" ? each.value.startup_script : null

  dynamic "instance_market_options" {
    for_each = each.value.spot ? [1] : []
    content {
      market_type = "spot"
      spot_options {
        instance_interruption_behavior = "stop"
        spot_instance_type             = "persistent"
      }
    }
  }

  tags = merge(var.common_tags, each.value.tags, {
    Name = each.key
  })

  lifecycle {
    ignore_changes = [ami]
  }
}
