# main.tf

resource "azurerm_log_analytics_workspace" "this" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

resource "azurerm_virtual_machine_extension" "azure_monitor_agent" {
  for_each = var.vm_ids

  name = "AzureMonitorLinuxAgent"
  virtual_machine_id = each.value
  publisher = "Microsoft.Azure.Monitor"
  type = "AzureMonitorLinuxAgent"
  type_handler_version = "1.41"
  auto_upgrade_minor_version = true
}
