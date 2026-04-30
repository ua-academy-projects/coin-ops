locals {
  # Combine single protocol and multi-protocol into one list
  all_protocols = compact(concat(
    var.protocols,
    var.protocol != null ? [var.protocol] : []
  ))
}

resource "google_compute_firewall" "this" {
  name        = var.name
  project     = var.project_id
  network     = var.network_self_link
  description = var.description

  # ----------------------------------------------------------------------------
  # Allow blocks — created dynamically per protocol
  # ----------------------------------------------------------------------------
  dynamic "allow" {
    for_each = local.all_protocols

    content {
      protocol = allow.value
      # ICMP has no ports — only set ports for tcp/udp
      ports = contains(["tcp", "udp"], allow.value) ? var.ports : []
    }
  }

  # ----------------------------------------------------------------------------
  # Source — either IP ranges or tags (not both at the same time)
  # ----------------------------------------------------------------------------
  source_ranges = length(var.source_ranges) > 0 ? var.source_ranges : null
  source_tags   = length(var.source_tags) > 0 ? var.source_tags : null

  # ----------------------------------------------------------------------------
  # Target — which VMs this rule applies to
  # ----------------------------------------------------------------------------
  target_tags = var.target_tags
}