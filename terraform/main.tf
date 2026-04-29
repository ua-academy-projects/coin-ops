# Create a VPC network 
resource "google_compute_network" "vpc_network" {
  name                    = "vpc-network"
  auto_create_subnetworks = false
  description             = "VPC network for two subnets: internal and external"
}

# Create two subnets: one for internal communication and another for external access
resource "google_compute_subnetwork" "internal_subnet" {
  name          = "internal-subnet"
  ip_cidr_range = "10.10.1.0/24"
  region        = var.region
  network       = google_compute_network.vpc_network.id
}

resource "google_compute_subnetwork" "external_subnet" {
  name          = "external-subnet"
  ip_cidr_range = "10.10.2.0/24"
  region        = var.region
  network       = google_compute_network.vpc_network.id
}

# Create a firewall rule to allow internal communication between the subnets
resource "google_compute_firewall" "internal_firewall" {
  name    = "allow-internal-communication"
  network = google_compute_network.vpc_network.id

  allow {
    protocol = "tcp"
    ports    = ["22"] # Allow SSH traffic between subnets
  }

  allow {
    protocol = "icmp" # Allow ICMP traffic for ping between subnets
  }

  source_tags = ["jump-host"] # Allow traffic from jump host to internal subnet
  target_tags   = ["internal-vm"] # Apply this rule to internal VMs
}

# Create a firewall rule to allow external access to the external subnet
resource "google_compute_firewall" "external_firewall" {
  name    = "allow-external-access"
  network = google_compute_network.vpc_network.id

  allow {
    protocol = "tcp"
    ports    = ["22"] # Allow SSH traffic from anywhere to external subnet
  }

  allow {
    protocol = "icmp" # Allow ICMP traffic for ping between subnets
  }

  source_ranges = ["0.0.0.0/0"] # Allow traffic from anywhere to external subnet
  target_tags   = ["jump-host"]
}

# Create 3 VMs in the internal subnet without external IP addresses
resource "google_compute_instance" "internal_vm" {
  count        = 3
  name         = "internal-vm-${count.index + 1}"
  machine_type = "e2-micro"
  zone         = "${var.region}-a"
  tags         = ["internal-vm"]

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
    }
  }

  network_interface {
    network    = google_compute_network.vpc_network.id
    subnetwork = google_compute_subnetwork.internal_subnet.id
  }
}

# Create Jump host in the external subnet
resource "google_compute_instance" "jump_host" {
  name         = "jump-host"
  machine_type = "e2-micro"
  zone         = "${var.region}-a"
  tags         = ["jump-host"]

  metadata_startup_script = <<-EOT
    sleep 10
    sudo apt update -y
    sudo apt upgrade -y
  EOT

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
    }
  }

  network_interface {
    network    = google_compute_network.vpc_network.id
    subnetwork = google_compute_subnetwork.external_subnet.id
    access_config {}
  }
}