locals {
  bastion_outputs = {
    for name, instance in azurerm_linux_virtual_machine.bastion : name => {
      name       = var.instances[name].name
      role       = "bastion"
      private_ip = azurerm_network_interface.bastion[name].private_ip_address
      public_ip  = azurerm_public_ip.bastion[name].ip_address
    }
  }

  app_outputs = {
    for name, instance in azurerm_linux_virtual_machine.app : name => {
      name       = var.instances[name].name
      role       = "app"
      private_ip = azurerm_network_interface.app[name].private_ip_address
      public_ip  = ""
    }
  }
}

output "instances" {
  value = merge(local.bastion_outputs, local.app_outputs)
}

output "app_instances" {
  value = {
    for name, instance in azurerm_linux_virtual_machine.app : name => merge(local.app_outputs[name], {
      id                    = instance.id
      nic_id                = azurerm_network_interface.app[name].id
      ip_configuration_name = "primary"
      principal_id          = instance.identity[0].principal_id
    })
  }
}
