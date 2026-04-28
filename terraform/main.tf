resource "google_compute_network" "test_vpc" {
  name                    = "test-network"
  auto_create_subnetworks = false
  description             = "Test VPC network to validate bootstrap script and Terraform configuration"
}

resource "google_compute_subnetwork" "test_subnet" {
  name          = "test-subnet"
  ip_cidr_range = "10.10.1.0/24"
  region        = var.region
  network       = google_compute_network.test_vpc.id
}

resource "google_compute_instance" "test_vm" {
  name         = "test-vm"
  machine_type = "e2-micro"
  zone         = "${var.region}-a"

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
    }
  }

  service_account {
    # Порожній email означає використання дефолтного акаунта проекту
    email  = "" 
    scopes = ["cloud-platform"]
  }

  network_interface {
    network = google_compute_network.test_vpc.id
    subnetwork = google_compute_subnetwork.test_subnet.id
    access_config {}
  }
}