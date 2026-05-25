locals {
  secret_prefix = trim(try(var.secrets.prefix, var.name_prefix), "/")

  secret_item_names = {
    for key, value in try(var.secrets.items, {}) :
    key => try(value.name, tostring(value))
  }
}

resource "aws_secretsmanager_secret" "this" {
  for_each = local.secret_item_names

  name = "${local.secret_prefix}/${each.value}"
  # 0 = purge immediately on destroy (no 7-day deletion window). Right for a
  # throwaway lab that's destroyed/recreated often — avoids "secret already
  # scheduled for deletion" collisions on the next apply. Raise to 7-30 for
  # production where an accidental destroy should be recoverable.
  recovery_window_in_days = 0

  tags = {
    Name = "${local.secret_prefix}/${each.value}"
  }
}
