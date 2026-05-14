locals {
  aws_enabled = lower(var.cloud) == "aws"
}

resource "aws_key_pair" "main" {
  count      = local.aws_enabled ? 1 : 0
  key_name   = "${var.network_name}-${var.ssh_user}"
  public_key = file(pathexpand(var.public_key_path))
}
