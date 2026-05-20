locals {
  name         = "${var.stack.name_prefix}-ui"
  machine_type = var.stack.instances[var.stack.app_names[0]].gcp_machine_type
  image        = var.stack.image_catalog[try(var.stack.defaults.image, "ubuntu_2204")].gcp
  subnet_cidr  = cidrsubnet(var.stack.network.cidr, 8, 42)

  metadata_startup_script = <<-EOT
  #!/bin/bash
  set -euo pipefail
  apt-get update
  apt-get install -y python3
  EOT

  ssh_config = <<-EOT
  Host ${local.name}
    HostName ${google_compute_instance.ui.network_interface[0].access_config[0].nat_ip}
    User ${var.stack.ssh.user}
    IdentityFile ${var.stack.ssh.private_key_path}
    IdentitiesOnly yes
    UserKnownHostsFile ${var.known_hosts_file}
    StrictHostKeyChecking accept-new
  EOT

  ansible_inventory = <<-EOT

  [ui]
  ${local.name} ansible_host=${google_compute_instance.ui.network_interface[0].access_config[0].nat_ip}

  [cloud:children]
  ui

  [ui:vars]
  coinops_ssh_common_args='-o UserKnownHostsFile=${var.known_hosts_file} -o StrictHostKeyChecking=accept-new'
  EOT
}

resource "google_compute_network" "this" {
  name                    = "${local.name}-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "public" {
  name          = "${local.name}-subnet"
  ip_cidr_range = local.subnet_cidr
  region        = var.stack.gcp.region
  network       = google_compute_network.this.id
}

resource "google_compute_firewall" "ssh" {
  name    = "${local.name}-ssh"
  network = google_compute_network.this.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = try(var.stack.firewall.ssh_source_ranges, [])
  target_tags   = ["ui"]
}

resource "google_compute_firewall" "http" {
  name    = "${local.name}-http"
  network = google_compute_network.this.name

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }

  source_ranges = try(var.stack.firewall.web_source_ranges, ["0.0.0.0/0"])
  target_tags   = ["ui"]
}

resource "google_compute_address" "ui" {
  name   = "${local.name}-ip"
  region = var.stack.gcp.region
}

resource "google_compute_instance" "ui" {
  name         = local.name
  machine_type = local.machine_type
  zone         = var.stack.gcp.zone
  tags         = ["ui"]

  boot_disk {
    initialize_params {
      image = local.image
      size  = try(var.stack.defaults.disk_size_gb, 10)
      type  = "pd-balanced"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.public.id

    access_config {
      nat_ip = google_compute_address.ui.address
    }
  }

  metadata = {
    ssh-keys = "${var.stack.ssh.user}:${var.stack.ssh_public_key}"
  }

  metadata_startup_script = local.metadata_startup_script
}
