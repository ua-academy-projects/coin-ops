# ----------------------------------------------------------------------------
# VPC Network
# ----------------------------------------------------------------------------
resource "google_compute_network" "vpc" {
  name                    = var.network_name
  auto_create_subnetworks = false
  description             = "VPC network managed by Terraform"
}

# ----------------------------------------------------------------------------
# Subnet
# ----------------------------------------------------------------------------
resource "google_compute_subnetwork" "subnet" {
  name          = "${var.network_name}-subnet"
  ip_cidr_range = var.subnet_cidr
  region        = var.region
  network       = google_compute_network.vpc.id
  description   = "Primary subnet managed by Terraform"
}

# ----------------------------------------------------------------------------
# SSH Key Metadata (project-wide)
# ----------------------------------------------------------------------------
resource "google_compute_project_metadata" "ssh_keys" {
  metadata = {
    ssh-keys = "terraform:${file("~/.ssh/gcp_jump.pub")}"
  }
}

# ----------------------------------------------------------------------------
# Firewall — Allow SSH to Jump Host from your IP only
# ----------------------------------------------------------------------------
resource "google_compute_firewall" "allow_ssh_jump" {
  name    = "allow-ssh-jump-host"
  network = google_compute_network.vpc.id

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = [var.ssh_source_ip]
  target_tags   = ["jump-host"]

  description = "Allow SSH to jump host from trusted IP only"
}

# ----------------------------------------------------------------------------
# Firewall — Allow internal traffic between all VMs
# ----------------------------------------------------------------------------
resource "google_compute_firewall" "allow_internal" {
  name    = "allow-internal"
  network = google_compute_network.vpc.id

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

  source_ranges = [var.subnet_cidr]
  target_tags   = ["internal-vm"]

  description = "Allow all internal traffic between VMs in the subnet"
}

# ----------------------------------------------------------------------------
# Firewall — Allow SSH from Jump Host to internal VMs
# ----------------------------------------------------------------------------
resource "google_compute_firewall" "allow_ssh_from_jump" {
  name    = "allow-ssh-from-jump"
  network = google_compute_network.vpc.id

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_tags = ["jump-host"]
  target_tags = ["internal-vm"]

  description = "Allow SSH from jump host to internal VMs"
}

# ----------------------------------------------------------------------------
# VM1, VM2, VM3 — Internal only (no public IP)
# ----------------------------------------------------------------------------
resource "google_compute_instance" "internal_vm" {
  count        = 3
  name         = "vm-${count.index + 1}"
  machine_type = var.machine_type
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 10
      type  = "pd-standard"
    }
  }

  network_interface {
    network    = google_compute_network.vpc.id
    subnetwork = google_compute_subnetwork.subnet.id
    # No access_config = no public IP
  }

  tags = ["internal-vm", "terraform-managed"]

  labels = {
    managed-by  = "terraform"
    environment = var.environment
    role        = "internal"
  }

  metadata = {
    enable-oslogin = "false"
  }
}

# ----------------------------------------------------------------------------
# VM4 — Jump Host (public + internal IP)
# ----------------------------------------------------------------------------
resource "google_compute_instance" "jump_host" {
  name         = "vm-4-jump"
  machine_type = var.machine_type
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 10
      type  = "pd-standard"
    }
  }

  network_interface {
    network    = google_compute_network.vpc.id
    subnetwork = google_compute_subnetwork.subnet.id

    access_config {
      # This block gives the VM a public IP
    }
  }

  tags = ["jump-host", "terraform-managed"]

  labels = {
    managed-by  = "terraform"
    environment = var.environment
    role        = "jump-host"
  }

  metadata = {
    enable-oslogin = "false"
  }
}