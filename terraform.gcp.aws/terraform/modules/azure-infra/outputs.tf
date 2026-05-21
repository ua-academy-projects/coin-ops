output "resource_group_name" {
  value = local.resource_group_name
}

output "bastion_external_ip" {
  value = azurerm_public_ip.bastion.ip_address
}

output "bastion_internal_ip" {
  value = azurerm_network_interface.vms["bastion"].private_ip_address
}

output "private_internal_ips" {
  value = {
    app = azurerm_network_interface.vms["app"].private_ip_address
    web = azurerm_network_interface.vms["web"].private_ip_address
  }
}

output "load_balancer_dns_name" {
  value = null
}

output "load_balancer_ip_address" {
  value = azurerm_public_ip.web.ip_address
}

output "external_db_host" {
  value = length(azurerm_postgresql_flexible_server.postgres) > 0 ? azurerm_postgresql_flexible_server.postgres[0].fqdn : null
}

output "network_id" {
  value = azurerm_virtual_network.main.id
}

output "subnet_ids" {
  value = {
    for name, subnet in azurerm_subnet.subnets : name => subnet.id
  }
}
