# --- Network ---
resource "google_compute_network" "vpc" {
  name                    = "devops-network"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "subnet" {
  name          = "devops-subnet"
  ip_cidr_range = "10.0.1.0/24"
  region        = var.region
  network       = google_compute_network.vpc.id
}

# --- Firewall: allow SSH from internet to jump host only ---
resource "google_compute_firewall" "allow_ssh_external" {
  name    = "allow-ssh-external"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["jump-host"]
}

# --- Firewall: allow SSH from jump host to internal VMs ---
resource "google_compute_firewall" "allow_ssh_internal" {
  name    = "allow-ssh-internal"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_tags = ["jump-host"]
  target_tags = ["internal"]
}

# --- Firewall: allow internal VMs to talk to each other ---
resource "google_compute_firewall" "allow_internal" {
  name    = "allow-internal"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
  }

  allow {
    protocol = "udp"
  }

  allow {
    protocol = "icmp"
  }

  source_tags = ["internal"]
  target_tags = ["internal"]
}

# --- Jump Host (external + internal IP) ---
resource "google_compute_instance" "jump_host" {
  name         = "jump-host"
  machine_type = "e2-micro"
  zone         = var.zone
  tags         = ["jump-host"]

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2404-lts-amd64"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.subnet.id

    access_config {}
  }
}

# --- Internal VMs (internal IP only, no access_config) ---
resource "google_compute_instance" "internal_vm" {
  count        = 3
  name         = "internal-vm-${count.index + 1}"
  machine_type = "e2-micro"
  zone         = var.zone
  tags         = ["internal"]

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2404-lts-amd64"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.subnet.id
  }
}