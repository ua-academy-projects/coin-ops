locals {
  raw_prefix    = try(var.secrets.prefix, var.name_prefix)
  secret_prefix = replace(replace(local.raw_prefix, "/", "-"), "_", "-")

  secret_item_names = {
    for key, value in try(var.secrets.items, {}) :
    key => replace(replace(try(value.name, tostring(value)), "/", "-"), "_", "-")
    if key != "cloudflare_token"
  }
}

resource "google_secret_manager_secret" "this" {
  for_each = local.secret_item_names

  secret_id = "${local.secret_prefix}-${each.value}"

  replication {
    auto {}
  }

  labels = {
    app = local.secret_prefix
  }
}
