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
# Test VM
# ----------------------------------------------------------------------------
resource "google_compute_instance" "test_vm" {
  name         = var.vm_name
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
  }

  tags = ["terraform-managed"]

  labels = {
    managed-by  = "terraform"
    environment = var.environment
  }
}
