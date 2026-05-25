resource "google_compute_network" "vpc" {
  count                   = contains(["gcp", "hybrid"], var.config.general.cloud) ? 1 : 0
  name                    = "devops-network"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "subnet" {
  count         = contains(["gcp", "hybrid"], var.config.general.cloud) ? 1 : 0
  name          = "devops-subnet"
  ip_cidr_range = "10.0.1.0/24"
  region        = var.config.locations[var.config.general.location].gcp.region
  network       = google_compute_network.vpc[0].id
}

# Cloud Router — required for Cloud NAT
resource "google_compute_router" "main" {
  count   = contains(["gcp", "hybrid"], var.config.general.cloud) ? 1 : 0
  name    = "devops-router"
  network = google_compute_network.vpc[0].id
  region  = var.config.locations[var.config.general.location].gcp.region
}

# Cloud NAT — gives private VMs outbound internet access
resource "google_compute_router_nat" "main" {
  count                              = contains(["gcp", "hybrid"], var.config.general.cloud) ? 1 : 0
  name                               = "devops-nat"
  router                             = google_compute_router.main[0].name
  region                             = var.config.locations[var.config.general.location].gcp.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}