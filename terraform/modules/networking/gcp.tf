# ═════════════════════════════════════════════════════════════════════════════
# GCP RESOURCES
# ═════════════════════════════════════════════════════════════════════════════

# ─── GCP VPC ─────────────────────────────────────────────────────────────────
resource "google_compute_network" "this" {
  count = var.cloud_provider == "gcp" ? 1 : 0

  name                    = var.vpc_name
  auto_create_subnetworks = false
  description             = "Managed by Terraform"
}

# ─── GCP Subnets ─────────────────────────────────────────────────────────────
resource "google_compute_subnetwork" "this" {
  for_each = var.cloud_provider == "gcp" ? local.resolved_subnets : {}

  name                     = each.key
  ip_cidr_range            = each.value.cidr
  region                   = local.region
  network                  = google_compute_network.this[0].id
  private_ip_google_access = true
  description              = "Managed by Terraform"
}

# ─── GCP Firewall Rules ─────────────────────────────────────────────────────
resource "google_compute_firewall" "this" {
  for_each = var.cloud_provider == "gcp" ? var.firewall_rules : {}

  name        = each.key
  network     = google_compute_network.this[0].id
  description = each.value.description
  direction   = upper(each.value.direction)
  priority    = try(each.value.priority, 1000)
  dynamic "allow" {
    for_each = each.value.action == "allow" ? [1] : []
    content {
      protocol = each.value.protocol
      ports    = each.value.protocol == "all" ? null : (each.value.port == 0 ? null : [tostring(each.value.port)])
    }
  }

  dynamic "deny" {
    for_each = each.value.action == "deny" ? [1] : []
    content {
      protocol = each.value.protocol
      ports    = each.value.protocol == "all" ? null : (each.value.port == 0 ? null : [tostring(each.value.port)])
    }
  }

  source_ranges      = upper(each.value.direction) == "INGRESS" && length(each.value.source_cidrs) > 0 ? each.value.source_cidrs : null
  destination_ranges = upper(each.value.direction) == "EGRESS" && length(each.value.destination_cidrs) > 0 ? each.value.destination_cidrs : null
  
  source_tags        = upper(each.value.direction) == "INGRESS" && each.value.source_group != "" ? [each.value.source_group] : null
  target_tags        = each.value.target_group != "" ? [each.value.target_group] : null
}

# ─── GCP Cloud NAT ───────────────────────────────────────────────────────────
# Allows private instances to reach the internet (for updates/docker pulls)
resource "google_compute_router" "router" {
  count   = var.cloud_provider == "gcp" ? 1 : 0
  name    = "${var.vpc_name}-router"
  region  = local.region
  network = google_compute_network.this[0].id
}

resource "google_compute_router_nat" "nat" {
  count                              = var.cloud_provider == "gcp" ? 1 : 0
  name                               = "${var.vpc_name}-nat"
  router                             = google_compute_router.router[0].name
  region                             = local.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}
