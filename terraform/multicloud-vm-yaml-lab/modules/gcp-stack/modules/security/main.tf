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

# Operator access through the bastion: k3s API server (6443), the
# hello-world NodePort (30080), and the Headlamp dashboard NodePort
# (30081). The bastion is the tailnet subnet router and SNATs forwarded
# traffic to its own IP, so tailnet clients reaching k3s appear to come
# from the bastion tag here. No tailnet-CIDR rule is needed: k3s nodes run
# no Tailscale, all tailnet access arrives via the bastion route.
resource "google_compute_firewall" "k3s_from_bastion" {
  count = length(var.k3s_target_tags) > 0 ? 1 : 0

  name      = "${var.name_prefix}-allow-k3s-from-bastion"
  network   = var.network_self_link
  direction = "INGRESS"

  source_tags = var.bastion_target_tags
  target_tags = var.k3s_target_tags

  allow {
    protocol = "tcp"
    ports    = ["6443", "30080", "30081"]
  }
}
