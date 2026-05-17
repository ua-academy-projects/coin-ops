output "private_ip" {
    value = azurerm_linux_virtual_machine.this.private_ip_address
}

output "public_ip" {
  value = var.public_ip ? azurerm_public_ip.this[0].ip_address : null
}