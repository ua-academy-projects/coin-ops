resource "google_compute_network" "main" {
  name                    = var.network.name
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "public" {
  for_each = var.network.public_subnets

  name          = each.value.name
  ip_cidr_range = each.value.cidr
  region        = var.region
  network       = google_compute_network.main.id
}

resource "google_compute_subnetwork" "private" {
  for_each = var.network.private_subnets

  name                     = each.value.name
  ip_cidr_range            = each.value.cidr
  region                   = var.region
  network                  = google_compute_network.main.id
  private_ip_google_access = true
}

resource "google_compute_router" "nat" {
  name    = "${var.name_prefix}-router"
  network = google_compute_network.main.id
  region  = var.region
}

resource "google_compute_router_nat" "this" {
  name                               = "${var.name_prefix}-nat"
  router                             = google_compute_router.nat.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  dynamic "subnetwork" {
    for_each = google_compute_subnetwork.private
    content {
      name                    = subnetwork.value.self_link
      source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
    }
  }
}
