locals {
  host = try(google_memorystore_instance.this.endpoints[0].connections[0].psc_auto_connection[0].ip_address, "")
  port = try(google_memorystore_instance.this.endpoints[0].connections[0].psc_auto_connection[0].port, var.runtime.cache.port)
}

output "cache" {
  value = {
    managed   = true
    backend   = "valkey"
    engine    = "valkey"
    host      = local.host
    port      = local.port
    redis_url = "redis://${local.host}:${local.port}/0"
    id        = google_memorystore_instance.this.id
  }
}
