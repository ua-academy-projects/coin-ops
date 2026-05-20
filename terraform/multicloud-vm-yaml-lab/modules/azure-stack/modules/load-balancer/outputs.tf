output "public_ip_address" {
  value = azurerm_public_ip.api.ip_address
}

output "backend_pool_id" {
  value = one(azurerm_application_gateway.api.backend_address_pool).id
}

output "load_balancer" {
  value = {
    dns_name         = azurerm_public_ip.api.ip_address
    zone_id          = ""
    https_enabled    = local.https_enabled
    target_group_arn = one(azurerm_application_gateway.api.backend_address_pool).id
  }
}
