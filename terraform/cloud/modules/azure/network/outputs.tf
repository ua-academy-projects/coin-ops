# outputs.tf

output "network_name" {
  value = azurerm_virtual_network.this.name
}

output "network_id" {
  value = azurerm_virtual_network.this.id
}

output "subnetwork_names" {
  value = { for key, subnet in azurerm_subnet.this : key => subnet.name }
}

output "subnetwork_ids" {
  value = { for key, subnet in azurerm_subnet.this : key => subnet.id }
}

output "private_subnet_ids" {
  value = {
    for key, subnet in azurerm_subnet.this : key => subnet.id
    if contains(keys(local.private_subnets), key)
  }
}
