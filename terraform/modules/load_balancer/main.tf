# =============================================================================
# modules/load_balancer/main.tf
# =============================================================================
# Cloud-agnostic load balancer logic. Provider-specific resources live in:
#   - gcp.tf  (Google Cloud — Global HTTP(S) LB)
#   - aws.tf  (Amazon Web Services — Application Load Balancer)
# =============================================================================

locals {
  # ── Resolve provider-specific region ────────────────────────────────────────
  region = var.region

  # ── Group backends by zone (needed for GCP unmanaged instance groups) ───────
  # Produces: { "us-central1-a" = ["vm-a", "vm-b"], "us-central1-b" = ["vm-c"] }
  backends_by_zone = {
    for zone in distinct([for b in values(var.backends) : b.zone]) :
    zone => [
      for name, b in var.backends : name
      if b.zone == zone
    ]
  }
}
