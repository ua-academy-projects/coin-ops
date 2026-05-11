locals {
  secret_prefix = trim(try(var.secrets.prefix, var.name_prefix), "/")

  secret_item_names = {
    for key, value in try(var.secrets.items, {}) :
    key => try(value.name, tostring(value))
    if key != "cloudflare_token"
  }
}

resource "aws_secretsmanager_secret" "this" {
  for_each = local.secret_item_names

  name                    = "${local.secret_prefix}/${each.value}"
  recovery_window_in_days = 7

  tags = {
    Name = "${local.secret_prefix}/${each.value}"
  }
}
