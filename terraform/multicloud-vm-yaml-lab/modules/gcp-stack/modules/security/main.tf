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
