# =============================================================================
# k3s/network.tf
# =============================================================================
# Provisions the complete GCP network foundation:
#
#   ┌──────────────────────────────────────────────────────────────────────┐
#   │  k3s-ha-vpc                                                          │
#   │                                                                       │
#   │  ┌─── public-subnet (10.10.0.0/24) ───────────────────────────────┐  │
#   │  │   Bastion Host (e2-micro, ephemeral external IP for IAP)       │  │
#   │  └────────────────────────────────────────────────────────────────┘  │
#   │                                                                       │
#   │  ┌─── private-subnet (10.10.1.0/24) ──────────────────────────────┐  │
#   │  │   k3s-node-0  (zone-a)  ─┐                                    │  │
#   │  │   k3s-node-1  (zone-b)   ├── NO external IP, egress via NAT  │  │
#   │  │   k3s-node-2  (zone-c)  ─┘                                    │  │
#   │  └────────────────────────────────────────────────────────────────┘  │
#   │                                                                       │
#   │  Cloud Router + Cloud NAT (private → internet, e.g. k3s install)    │
#   └──────────────────────────────────────────────────────────────────────┘
#
# Firewall rule summary:
#   allow-iap-ssh-bastion        – IAP (35.235.240.0/20) → Bastion:22
#   allow-bastion-ssh-k3s        – Bastion (tag) → k3s nodes:22
#   allow-internal-k3s           – k3s nodes ↔ k3s nodes (full mesh)
#   allow-lb-to-k3s-api          – GCP LB health-check ranges → :6443
#   allow-nginx-ingress          – 0.0.0.0/0 → LB forwarding rule → :80/:443
#   deny-all-ingress-private      – catch-all deny for private subnet
# =============================================================================

# ─── VPC ─────────────────────────────────────────────────────────────────────

resource "google_compute_network" "vpc" {
  name                    = local.vpc_name
  auto_create_subnetworks = false
  description             = "k3s HA cluster VPC — managed by Terraform"
}

# ─── Subnets ──────────────────────────────────────────────────────────────────

# Public subnet: only the Bastion Host resides here.
resource "google_compute_subnetwork" "public" {
  name                     = "${local.vpc_name}-public"
  ip_cidr_range            = local.public_subnet_cidr
  region                   = local.region
  network                  = google_compute_network.vpc.id
  private_ip_google_access = true
  description              = "Public subnet — Bastion Host only"
}

# Private subnet: all k3s control-plane nodes, no external IPs.
resource "google_compute_subnetwork" "private" {
  name                     = "${local.vpc_name}-private"
  ip_cidr_range            = local.private_subnet_cidr
  region                   = local.region
  network                  = google_compute_network.vpc.id
  private_ip_google_access = true # allows Google APIs without NAT
  description              = "Private subnet — k3s control-plane nodes"
}

# ─── Cloud Router & NAT ───────────────────────────────────────────────────────
# Private VMs use Cloud NAT to reach the internet (k3s install, docker pulls).
# Outbound traffic is NATed through auto-allocated ephemeral Google IPs.

resource "google_compute_router" "nat_router" {
  name    = "${local.vpc_name}-router"
  region  = local.region
  network = google_compute_network.vpc.id

  bgp {
    asn = 64514
  }
}

resource "google_compute_router_nat" "nat" {
  name                               = "${local.vpc_name}-nat"
  router                             = google_compute_router.nat_router.name
  region                             = local.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  # NAT only the private subnet; the public subnet has direct internet access.
  subnetwork {
    name                    = google_compute_subnetwork.private.id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# ─── Firewall Rules ───────────────────────────────────────────────────────────

# 1. Allow IAP to SSH into the Bastion Host.
#    GCP Identity-Aware Proxy always originates from 35.235.240.0/20.
#    This replaces direct internet SSH — no TCP:22 is open to 0.0.0.0/0.
resource "google_compute_firewall" "allow_iap_ssh_bastion" {
  name        = "${local.vpc_name}-allow-iap-ssh-bastion"
  network     = google_compute_network.vpc.id
  description = "Allow IAP proxy to SSH into the Bastion Host"
  direction   = "INGRESS"
  priority    = 1000

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  # IAP source range — never changes
  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["bastion"]
}

# 2. Allow Bastion → k3s nodes on port 22 only.
#    Uses network tags for least-privilege access control.
resource "google_compute_firewall" "allow_bastion_ssh_k3s" {
  name        = "${local.vpc_name}-allow-bastion-to-k3s-ssh"
  network     = google_compute_network.vpc.id
  description = "Bastion Host is the only SSH entry point into k3s nodes"
  direction   = "INGRESS"
  priority    = 1000

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_tags = ["bastion"]  # only traffic tagged 'bastion' is allowed
  target_tags = ["k3s-node"] # applies to all control-plane nodes
}

# 3. Internal k3s cluster traffic (etcd, k3s API, Cilium VXLAN/Geneve, etc.).
#    Nodes must reach each other on all ports within the private subnet.
resource "google_compute_firewall" "allow_internal_k3s" {
  name        = "${local.vpc_name}-allow-internal-k3s"
  network     = google_compute_network.vpc.id
  description = "Full mesh between k3s control-plane nodes (etcd + k3s + Cilium)"
  direction   = "INGRESS"
  priority    = 1000

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "icmp"
  }

  source_ranges = [local.private_subnet_cidr]
  target_tags   = ["k3s-node"]
}

# 4. Allow GCP health-check probes and Internal LB traffic to the k3s API port.
#    GCP internal load balancer health-check ranges: 130.211.0.0/22, 35.191.0.0/16
resource "google_compute_firewall" "allow_lb_to_k3s_api" {
  name        = "${local.vpc_name}-allow-lb-to-k3s-api"
  network     = google_compute_network.vpc.id
  description = "Allow GCP LB health-checks and internal LB VIP to reach k3s API (6443)"
  direction   = "INGRESS"
  priority    = 1000

  allow {
    protocol = "tcp"
    ports    = ["6443"]
  }

  source_ranges = [
    "130.211.0.0/22", # GCP health-check range 1
    "35.191.0.0/16",  # GCP health-check range 2
    local.private_subnet_cidr,
    local.public_subnet_cidr,
  ]
  target_tags = ["k3s-node"]
}

# 5. Allow NGINX Ingress traffic (HTTP/HTTPS) from the internet to nodes.
#    This is required for the external TCP passthrough Load Balancer that
#    fronts the NGINX Ingress NodePort service.
resource "google_compute_firewall" "allow_ingress_traffic" {
  name        = "${local.vpc_name}-allow-nginx-ingress"
  network     = google_compute_network.vpc.id
  description = "Allow external HTTP/HTTPS to NGINX Ingress NodePort on k3s nodes"
  direction   = "INGRESS"
  priority    = 1000

  allow {
    protocol = "tcp"
    ports    = ["80", "443", "30080", "30443"] # NodePort range for NGINX
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["k3s-node"]
}
