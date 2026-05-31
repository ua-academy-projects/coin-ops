# outputs.tf

output "instance_names" {
  value = { for key, instance in azurerm_linux_virtual_machine.this : key => instance.name }
}

output "private_ips" {
  value = { for key, nic in azurerm_network_interface.this : key => nic.private_ip_address }
}

output "public_ips" {
  value = merge(
    { for key, _ in var.workloads : key => null },
    { for key, pip in azurerm_public_ip.this : key => pip.ip_address }
  )
}

output "workload_identities" {
  value = {
    for key, vm in azurerm_linux_virtual_machine.this : key => {
      type         = "azure_managed_identity"
      principal_id = vm.identity[0].principal_id
    }
    if try(vm.identity[0].principal_id, null) != null
  }
}

output "workload_tags" {
  value = { for key, instance in local.instances : key => instance.tags }
}

output "managed_identity_principal_ids" {
  value = {
    for key, vm in azurerm_linux_virtual_machine.this : key => vm.identity[0].principal_id
    if try(vm.identity[0].principal_id, null) != null
  }
}
