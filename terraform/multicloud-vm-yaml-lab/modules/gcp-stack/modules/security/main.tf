locals {
  private_target_tags        = distinct(concat(var.app_target_tags, var.db_target_tags))
  load_balancer_source_cidrs = ["35.191.0.0/16", "130.211.0.0/22"]
}

resource "google_compute_firewall" "ssh_to_bastion" {
  name      = "${var.name_prefix}-allow-ssh-to-bastion"
  network   = var.network_self_link
  direction = "INGRESS"

  source_ranges = var.firewall.ssh_source_ranges
  target_tags   = var.bastion_target_tags

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

resource "google_compute_firewall" "ssh_from_bastion_to_private" {
  name      = "${var.name_prefix}-allow-ssh-bastion-to-private"
  network   = var.network_self_link
  direction = "INGRESS"

  source_tags = var.bastion_target_tags
  target_tags = local.private_target_tags

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

resource "google_compute_firewall" "app_from_load_balancer" {
  name      = "${var.name_prefix}-allow-app-from-lb"
  network   = var.network_self_link
  direction = "INGRESS"

  source_ranges = local.load_balancer_source_cidrs
  target_tags   = var.app_target_tags

  allow {
    protocol = "tcp"
    ports    = [tostring(var.app_port)]
  }
}

resource "google_compute_firewall" "db_from_app" {
  name      = "${var.name_prefix}-allow-db-from-app"
  network   = var.network_self_link
  direction = "INGRESS"

  source_tags = var.app_target_tags
  target_tags = var.db_target_tags

  allow {
    protocol = "tcp"
    ports    = ["5432", "5672", "6379"]
  }
}

resource "google_compute_firewall" "icmp_from_bastion_to_private" {
  count = var.allow_icmp_from_bastion ? 1 : 0

  name      = "${var.name_prefix}-allow-icmp-bastion-to-private"
  network   = var.network_self_link
  direction = "INGRESS"

  source_tags = var.bastion_target_tags
  target_tags = local.private_target_tags

  allow {
    protocol = "icmp"
  }
}

# k3s cluster-internal traffic: every node is both server and worker (HA
# embedded etcd), so all of these flow between any pair of cluster nodes.
# Scoped to the k3s tag, not the whole VPC.
resource "google_compute_firewall" "k3s_intra_cluster" {
  count = length(var.k3s_target_tags) > 0 ? 1 : 0

  name      = "${var.name_prefix}-allow-k3s-intra-cluster"
  network   = var.network_self_link
  direction = "INGRESS"

  source_tags = var.k3s_target_tags
  target_tags = var.k3s_target_tags

  # API server (6443), kubelet (10250), embedded etcd peer+client (2379-2380),
  # Flannel VXLAN backend (8472/udp).
  allow {
    protocol = "tcp"
    ports    = ["6443", "10250", "2379-2380"]
  }
  allow {
    protocol = "udp"
    ports    = ["8472"]
  }
}

# Operator access to the k3s API server. SSH still goes via the bastion;
# kubectl uses port 6443. Open from the bastion tag (so operator can run
# kubectl from inside the VPC) and from the Tailscale CGNAT range so any
# tailnet client can reach the API directly.
resource "google_compute_firewall" "k3s_api_from_bastion" {
  count = length(var.k3s_target_tags) > 0 ? 1 : 0

  name      = "${var.name_prefix}-allow-k3s-api-from-bastion"
  network   = var.network_self_link
  direction = "INGRESS"

  source_tags = var.bastion_target_tags
  target_tags = var.k3s_target_tags

  allow {
    protocol = "tcp"
    ports    = ["6443"]
  }
}

resource "google_compute_firewall" "k3s_api_from_tailnet" {
  count = length(var.k3s_target_tags) > 0 ? 1 : 0

  name      = "${var.name_prefix}-allow-k3s-api-from-tailnet"
  network   = var.network_self_link
  direction = "INGRESS"

  source_ranges = ["100.64.0.0/10"]
  target_tags   = var.k3s_target_tags

  allow {
    protocol = "tcp"
    ports    = ["6443"]
  }
}

# Hello-world NodePort access from the tailnet. The plan exposes the
# learning workload on :30080 — limit the NodePort range to just that
# port rather than opening the full 30000-32767 range.
resource "google_compute_firewall" "k3s_nodeport_from_tailnet" {
  count = length(var.k3s_target_tags) > 0 ? 1 : 0

  name      = "${var.name_prefix}-allow-k3s-nodeport-from-tailnet"
  network   = var.network_self_link
  direction = "INGRESS"

  source_ranges = ["100.64.0.0/10"]
  target_tags   = var.k3s_target_tags

  allow {
    protocol = "tcp"
    ports    = ["30080"]
  }
}
