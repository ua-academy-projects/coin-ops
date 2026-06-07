output "resource_group_name" {
  value = data.azurerm_resource_group.nav.name
}

output "vm_public_ip" {
  value = azurerm_public_ip.nav.ip_address
}

output "vm_public_fqdn" {
  value = azurerm_public_ip.nav.fqdn
}

output "ssh_command" {
  value = "ssh ${var.admin_username}@${azurerm_public_ip.nav.ip_address}"
}

output "cpu_alert_name" {
  value = azurerm_monitor_metric_alert.nav.name
}

output "action_group_name" {
  value = azurerm_monitor_action_group.nav.name
}
