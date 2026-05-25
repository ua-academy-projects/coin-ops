# =============================================================================
# k3s/loadbalancer.tf
# =============================================================================
# Provisions two GCP TCP Load Balancers:
#
#   1. INTERNAL TCP LB (k3s API — port 6443)
#      ─────────────────────────────────────
#      Regional internal passthrough LB.
#      Fronts all 3 control-plane nodes. Used by:
#        • kubectl (via SSH tunnel through Bastion)
#        • Helm/Kubernetes Terraform providers
#        • Node-to-node k3s server communication
#
#      Architecture:
#        kubectl → SSH tunnel (Bastion) → Internal LB VIP:6443 → k3s nodes
#
#   2. EXTERNAL TCP LB (NGINX Ingress — ports 80/443)
#      ────────────────────────────────────────────────
#      Regional external passthrough LB.
#      Fronts all 3 nodes on NodePort 30080 (HTTP) and 30443 (HTTPS).
#      Used for serving application traffic through NGINX Ingress.
#
#      Architecture:
#        Internet → External LB → k3s nodes (NodePort) → NGINX Ingress Pod
# =============================================================================

# ─── Instance Group (one unmanaged group per zone) ────────────────────────────
# Unmanaged groups are the simplest way to reference specific VMs in a backend.

resource "google_compute_instance_group" "k3s" {
  count = local.k3s_node_count
  name  = "k3s-node-group-${count.index}"
  zone  = local.mappings.zone_map[local.compute_cfg.nodes[count.index].zone]["gcp"]

  instances = [google_compute_instance.k3s_nodes[count.index].self_link]

  named_port {
    name = "k3s-api"
    port = 6443
  }

  named_port {
    name = "http"
    port = 30080
  }

  named_port {
    name = "https"
    port = 30443
  }
}

# ═════════════════════════════════════════════════════════════════════════════
# 1. INTERNAL TCP LB — k3s API Server (port 6443)
# ═════════════════════════════════════════════════════════════════════════════

# Health check: TCP probe against port 6443 (k3s API handshake)
resource "google_compute_region_health_check" "k3s_api" {
  name               = "k3s-api-health-check"
  region             = local.region
  check_interval_sec = 10
  timeout_sec        = 5
  healthy_threshold  = 2
  unhealthy_threshold = 3

  tcp_health_check {
    port = 6443
  }
}

# Backend service: internal passthrough, routes to all 3 node groups
resource "google_compute_region_backend_service" "k3s_api" {
  name                  = "k3s-api-backend"
  region                = local.region
  protocol              = "TCP"
  load_balancing_scheme = "INTERNAL"
  health_checks         = [google_compute_region_health_check.k3s_api.id]

  dynamic "backend" {
    for_each = google_compute_instance_group.k3s
    content {
      group          = backend.value.id
      balancing_mode = "CONNECTION"
    }
  }
}

# ─── Static internal IP for the k3s API LB ───────────────────────────────────
# Pre-allocated BEFORE the instances are created so that cloud-init templates
# can reference the VIP without creating a circular dependency.
# The instances reference this IP in --tls-san; the LB then uses it.
resource "google_compute_address" "k3s_api_vip" {
  name         = "k3s-api-lb-vip"
  region       = local.region
  address_type = "INTERNAL"
  subnetwork   = google_compute_subnetwork.private.id
  purpose      = "SHARED_LOADBALANCER_VIP"
  description  = "Static VIP for the k3s API internal load balancer"
}

# Forwarding rule: the internal VIP that everything targets for port 6443
resource "google_compute_forwarding_rule" "k3s_api" {
  name                  = "k3s-api-lb"
  region                = local.region
  load_balancing_scheme = "INTERNAL"
  ip_protocol           = "TCP"
  ip_address            = google_compute_address.k3s_api_vip.address
  ports                 = ["6443"]
  backend_service       = google_compute_region_backend_service.k3s_api.id
  network               = google_compute_network.vpc.id
  subnetwork            = google_compute_subnetwork.private.id

  # allow_global_access lets the Bastion in the public subnet reach the VIP
  allow_global_access = true
}


# ═════════════════════════════════════════════════════════════════════════════
# 2. EXTERNAL TCP LB — NGINX Ingress (ports 80/443)
# ═════════════════════════════════════════════════════════════════════════════

# Health check: TCP probe against NodePort 30080
resource "google_compute_region_health_check" "nginx_ingress" {
  name               = "nginx-ingress-health-check"
  region             = local.region
  check_interval_sec = 10
  timeout_sec        = 5
  healthy_threshold  = 2
  unhealthy_threshold = 3

  http_health_check {
    port         = 30080
    request_path = "/healthz"
  }
}

# Backend service: external passthrough
resource "google_compute_region_backend_service" "nginx_ingress" {
  name                  = "nginx-ingress-backend"
  region                = local.region
  protocol              = "TCP"
  load_balancing_scheme = "EXTERNAL"
  health_checks         = [google_compute_region_health_check.nginx_ingress.id]

  dynamic "backend" {
    for_each = google_compute_instance_group.k3s
    content {
      group          = backend.value.id
      balancing_mode = "CONNECTION"
    }
  }
}

# Reserve external IP for NGINX Ingress
resource "google_compute_address" "nginx_ingress_ip" {
  name   = "nginx-ingress-external-ip"
  region = local.region
}

# HTTP forwarding rule
resource "google_compute_forwarding_rule" "nginx_http" {
  name                  = "nginx-ingress-http"
  region                = local.region
  load_balancing_scheme = "EXTERNAL"
  ip_protocol           = "TCP"
  port_range            = "80"
  ip_address            = google_compute_address.nginx_ingress_ip.address
  backend_service       = google_compute_region_backend_service.nginx_ingress.id
}

# HTTPS forwarding rule (uses same external IP for consistent DNS)
resource "google_compute_forwarding_rule" "nginx_https" {
  name                  = "nginx-ingress-https"
  region                = local.region
  load_balancing_scheme = "EXTERNAL"
  ip_protocol           = "TCP"
  port_range            = "443"
  ip_address            = google_compute_address.nginx_ingress_ip.address
  backend_service       = google_compute_region_backend_service.nginx_ingress.id
}
