# main.tf

resource "google_compute_firewall" "this" {
  for_each = local.rules

  name        = each.value.name
  network     = var.network_name
  description = each.value.description
  direction   = each.value.direction
  priority    = each.value.priority

  source_ranges = length(each.value.source_ranges) > 0 ? each.value.source_ranges : null
  source_tags   = length(each.value.source_tags) > 0 ? each.value.source_tags : null
  target_tags   = length(each.value.target_tags) > 0 ? each.value.target_tags : null

  dynamic "allow" {
    for_each = each.value.allows

    content {
      protocol = allow.value.protocol
      ports    = length(allow.value.ports) > 0 ? allow.value.ports : null
    }
  }
}
