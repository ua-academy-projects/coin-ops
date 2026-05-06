locals {
  fallback_rules = {
    "allow-ssh-external" = {
      protocols    = [{ protocol = "tcp", ports = ["22"] }]
      source_cidrs = ["0.0.0.0/0"]
      target_role  = "jump-host"
    }
    "allow-internal" = {
      protocols   = [{ protocol = "tcp", ports = ["22"] }, { protocol = "icmp" }]
      source_role = "jump-host"
      target_role = "internal-vm"
    }
  }

  # Both branches are serialised to strings first so the ternary compares
  # identical types (string), then decoded back once. This avoids Terraform's
  # strict structural type unification between objects with different key sets.
  rules = jsondecode(
    length(var.firewall_rules) > 0
      ? jsonencode(var.firewall_rules)
      : jsonencode(local.fallback_rules)
  )
}

resource "google_compute_firewall" "rule" {
  for_each = local.rules

  name    = each.key
  network = var.network_id

  dynamic "allow" {
    for_each = each.value.protocols
    content {
      protocol = allow.value.protocol
      ports    = lookup(allow.value, "ports", null)
    }
  }

  source_ranges = lookup(each.value, "source_cidrs", null)
  source_tags   = lookup(each.value, "source_role", null) != null ? [each.value.source_role] : null
  target_tags   = lookup(each.value, "target_role", null) != null ? [each.value.target_role] : null
}
