output "cache" {
  value = {
    managed             = true
    backend             = "valkey"
    host                = azurerm_redis_cache.this.hostname
    port                = azurerm_redis_cache.this.ssl_port
    redis_url           = ""
    azure_resource_name = azurerm_redis_cache.this.name
  }
}
