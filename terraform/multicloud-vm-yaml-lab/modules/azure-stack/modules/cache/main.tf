resource "azurerm_redis_cache" "this" {
  name                = "${var.safe_prefix}-${var.unique_suffix}-redis"
  location            = var.location
  resource_group_name = var.resource_group_name
  capacity            = var.runtime.cache.azure_capacity
  family              = var.runtime.cache.azure_family
  sku_name            = var.runtime.cache.azure_sku_name
  minimum_tls_version = "1.2"
}
