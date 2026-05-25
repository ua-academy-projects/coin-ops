# =============================================================================
# k3s/providers.tf
# =============================================================================
# Configure all providers.
#
# The helm and kubernetes providers use an SSH tunnel through the Bastion Host
# to reach the k3s API server (port 6443) on the internal load balancer.
# The tunnel is established transparently via the "exec" plugin mechanism.
#
# NOTE: The helm/kubernetes providers are intentionally configured AFTER the
# k3s cluster is bootstrapped. Terraform's dependency graph ensures they only
# activate once the google resources (including the k3s nodes) exist.
# =============================================================================

provider "google" {
  project = local.project_id
  region  = local.region
}

# ─── TLS provider (generates SSH keypair for node provisioning) ───────────────
provider "tls" {}

# ─── Time provider (waits for k3s API to be healthy) ─────────────────────────
provider "time" {}

# ─── Kubernetes provider ─────────────────────────────────────────────────────
# Points at the internal LB IP via an SSH tunnel through the Bastion.
# The exec plugin runs a local `gcloud compute ssh` command that opens
# a tunnel: localhost:16443 → <LB_IP>:6443
provider "kubernetes" {
  config_path = "${path.module}/.kube/config"
}

# ─── Helm provider ───────────────────────────────────────────────────────────
# Mirrors the kubernetes provider config — same tunnel, same cluster.
provider "helm" {
  kubernetes {
    config_path = "${path.module}/.kube/config"
  }
}
