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

locals {
  vm_config = jsondecode(file("${path.module}/config.json"))
}

module "compute_instances" {
  source   = "./modules/gcp_manage_instances"
  for_each = local.vm_config.instances

  name            = each.key
  zone            = try(each.value.zone, local.vm_config.general.zone)

  machine_type    = try(each.value.machine_type, local.vm_config.general.machine_type)
  vpc_name        = try(each.value.vpc_name, local.vm_config.general.vpc_name) 
  subnet_name     = try(each.value.subnet_name, local.vm_config.general.subnet_name)
  has_external_ip = try(each.value.has_external_ip, local.vm_config.general.has_external_ip)
  tags            = try(each.value.tags, local.vm_config.general.tags)
  disk_size       = try(each.value.disk_size, local.vm_config.general.disk_size)
  os_image        = try(each.value.os_image, local.vm_config.general.os_image)

  depends_on = [
  google_compute_network.vpc_network,
  google_compute_subnetwork.external_subnet,
  google_compute_subnetwork.internal_subnet
  ]
}