output "application_security_group_ids" {
  value = { for key, asg in azurerm_application_security_group.workload : key => asg.id }
}

output "network_security_group_ids" {
  value = { for key, nsg in azurerm_network_security_group.subnet : key => nsg.id }
}
