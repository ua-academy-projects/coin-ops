# =============================================================================
# modules/networking/main.tf
# =============================================================================
# Cloud-agnostic networking logic. Resources are separated into:
# - gcp.tf (Google Cloud)
# - aws.tf (Amazon Web Services)
# =============================================================================

locals {
  # ── Resolve provider-specific region ────────────────────────────────────────
  region = var.region_map[var.region][var.cloud_provider]

  # ── Resolve provider-specific zones for subnets ────────────────────────────
  resolved_subnets = {
    for name, subnet in var.subnets : name => merge(subnet, {
      zone = subnet.zone_map[var.cloud_provider]
    })
  }
}
