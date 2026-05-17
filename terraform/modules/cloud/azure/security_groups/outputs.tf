output "nsg_ids" {
  value = { for role, nsg in azurerm_network_security_group.nsg : role => nsg.id }
}

output "asg_ids" {
  value = { for role, asg in azurerm_application_security_group.asg : role => asg.id }
}
