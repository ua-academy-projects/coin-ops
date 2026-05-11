resource "google_compute_firewall" "ssh_to_bastion" {
  name      = "${var.name_prefix}-allow-ssh-to-bastion"
  network   = var.network
  direction = "INGRESS"

  source_ranges = var.ssh_source_ranges
  target_tags   = var.bastion_target_tags

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

resource "google_compute_firewall" "ssh_from_bastion_to_private" {
  name      = "${var.name_prefix}-allow-ssh-bastion-to-private"
  network   = var.network
  direction = "INGRESS"

  source_tags = var.bastion_target_tags
  target_tags = var.private_target_tags

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

resource "google_compute_firewall" "icmp_from_bastion_to_private" {
  count = var.allow_icmp_from_bastion ? 1 : 0

  name      = "${var.name_prefix}-allow-icmp-bastion-to-private"
  network   = var.network
  direction = "INGRESS"

  source_tags = var.bastion_target_tags
  target_tags = var.private_target_tags

  allow {
    protocol = "icmp"
  }
}
