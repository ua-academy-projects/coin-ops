output "jump_host_external_ip" {
  description = "Public IP of jump host"
  value       = try(azurerm_public_ip.vm["jump-host"].ip_address, null)
}

output "jump_host_internal_ip" {
  description = "Internal IP of jump host"
  value       = try(azurerm_network_interface.vm["jump-host"].private_ip_address, null)
}

output "internal_vm_ips" {
  description = "Internal IPs of all nodes except jump host"
  value = {
    for name, nic in azurerm_network_interface.vm :
    name => nic.private_ip_address
    if name != "jump-host"
  }
}

output "ui_instance_id" {
  description = "Resource ID of node-03 for load balancer"
  value       = try(azurerm_linux_virtual_machine.vm["node-03"].id, null)
}

output "ui_nic_id" {
  description = "Network interface ID of node-03 for load balancer"
  value       = try(azurerm_network_interface.vm["node-03"].id, null)
}