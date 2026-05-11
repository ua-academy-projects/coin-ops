locals {
  cache = var.runtime.cache
}

resource "google_network_connectivity_service_connection_policy" "memorystore" {
  name          = "${var.name_prefix}-valkey-scp"
  project       = var.project_id
  location      = var.region
  network       = var.network_self_link
  service_class = "gcp-memorystore"
  description   = "Private Service Connect policy for ${var.name_prefix} Valkey"

  psc_config {
    subnetworks = values(var.private_subnet_self_links)
    limit       = "2"
  }
}

resource "google_memorystore_instance" "this" {
  instance_id = "${var.name_prefix}-valkey"
  project     = var.project_id
  location    = var.region

  shard_count   = local.cache.gcp_shard_count
  replica_count = local.cache.gcp_replica_count
  node_type     = local.cache.gcp_node_type

  engine_version               = local.cache.gcp_engine_version
  authorization_mode           = "AUTH_DISABLED"
  transit_encryption_mode      = "TRANSIT_ENCRYPTION_DISABLED"
  deletion_protection_enabled  = false
  allow_fewer_zones_deployment = true

  desired_auto_created_endpoints {
    network    = var.network_self_link
    project_id = var.project_id
  }

  depends_on = [google_network_connectivity_service_connection_policy.memorystore]
}
