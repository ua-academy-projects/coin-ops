locals {
  config = yamldecode(file("${path.module}/config.yaml"))
  general = local.config.general
}

# --- Network ---
resource "google_compute_network" "vpc" {
  name                    = "devops-network"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "subnet" {
  name          = "devops-subnet"
  ip_cidr_range = "10.0.1.0/24"
  region        = local.general.region
  network       = google_compute_network.vpc.id
}

# --- Firewall: allow SSH from internet to jump host only ---
resource "google_compute_firewall" "allow_ssh_external" {
  name    = "allow-ssh-external"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = [local.general.ssh_port]
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
    ports    = [local.general.ssh_port]
  }

  source_tags = ["jump-host"]
  target_tags = ["internal"]
}

# --- Firewall: allow internal VMs to talk to each other ---
resource "google_compute_firewall" "allow_internal" {
  name    = "allow-internal"
  network = google_compute_network.vpc.name

  allow { protocol = "tcp" }
  allow { protocol = "udp" }
  allow { protocol = "icmp" }

  source_tags = ["internal"]
  target_tags = ["internal"]
}

# --- VMs: one module call per VM defined in config.yaml ---
module "vm" {
  for_each = local.config.vms
  source   = "./modules/vm"

  name         = each.key
  machine_type = try(each.value.machine_type, local.general.machine_type)
  zone         = local.general.zone
  image        = try(each.value.image, local.general.image)
  disk_size    = try(each.value.disk_size, local.general.disk_size)
  tags         = each.value.tags
  public_ip    = each.value.public_ip
  subnetwork   = google_compute_subnetwork.subnet.id
  ssh_user     = local.general.ops_user
  ssh_public_key = file("${pathexpand("~")}/.ssh/id_ed25519.pub")
  ssh_port     = local.general.ssh_port
}