output "vm_id" {
  description = "ID of the virtual machine"
  value       = azurerm_linux_virtual_machine.this.id
}

output "vm_name" {
  description = "Name of the virtual machine"
  value       = azurerm_linux_virtual_machine.this.name
}

output "private_ip" {
  description = "Private IP address of the VM"
  value       = azurerm_linux_virtual_machine.this.private_ip_address
}

output "public_ip" {
  description = "Public IP address (null if not assigned)"
  value       = var.assign_public_ip ? azurerm_public_ip.this[0].ip_address : null
}
