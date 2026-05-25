resource "google_compute_firewall" "allow_ssh_external" {
  count   = contains(["gcp", "hybrid"], var.config.general.cloud) ? 1 : 0
  name    = "allow-ssh-external"
  network = var.vpc_name

  allow {
    protocol = "tcp"
    ports    = [var.config.general.ssh_port]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["jump-host"]
}

resource "google_compute_firewall" "allow_ssh_k3s" {
  count   = contains(["gcp", "hybrid"], var.config.general.cloud) ? 1 : 0
  name    = "allow-ssh-k3s"
  network = var.vpc_name

  allow {
    protocol = "tcp"
    ports    = [var.config.general.ssh_port]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["k3s-server"]
}

resource "google_compute_firewall" "allow_ssh_internal" {
  count   = contains(["gcp", "hybrid"], var.config.general.cloud) ? 1 : 0
  name    = "allow-ssh-internal"
  network = var.vpc_name

  allow {
    protocol = "tcp"
    ports    = [var.config.general.ssh_port]
  }

  source_tags = ["jump-host"]
  target_tags = ["internal"]
}

resource "google_compute_firewall" "allow_internal" {
  count   = contains(["gcp", "hybrid"], var.config.general.cloud) ? 1 : 0
  name    = "allow-internal"
  network = var.vpc_name

  allow { protocol = "tcp" }
  allow { protocol = "udp" }
  allow { protocol = "icmp" }

  source_tags = ["internal"]
  target_tags = ["internal"]
}

resource "google_compute_firewall" "allow_k3s" {
  count   = contains(["gcp", "hybrid"], var.config.general.cloud) ? 1 : 0
  name    = "allow-k3s"
  network = var.vpc_name

  allow {
    protocol = "tcp"
    ports    = ["6443"]
  }

  allow {
    protocol = "tcp"
    ports    = ["9345"]
  }

  allow {
    protocol = "tcp"
    ports    = ["2379-2380"]
  }

  allow {
    protocol = "udp"
    ports    = ["8472"]
  }

  allow {
    protocol = "tcp"
    ports    = ["10250"]
  }

  source_tags = ["k3s-server"]
  target_tags = ["k3s-server"]
}

# Allows kubectl access from internet to k3s API server
resource "google_compute_firewall" "allow_k3s_api_external" {
  count   = contains(["gcp", "hybrid"], var.config.general.cloud) ? 1 : 0
  name    = "allow-k3s-api-external"
  network = var.vpc_name

  allow {
    protocol = "tcp"
    ports    = ["6443"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["k3s-server"]
}