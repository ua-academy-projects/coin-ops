output "queue" {
  value = {
    managed                 = true
    backend                 = "azure_servicebus"
    name                    = azurerm_servicebus_queue.main.name
    queue_name              = azurerm_servicebus_queue.main.name
    namespace               = "${azurerm_servicebus_namespace.this.name}.servicebus.windows.net"
    servicebus_namespace    = "${azurerm_servicebus_namespace.this.name}.servicebus.windows.net"
    servicebus_namespace_id = azurerm_servicebus_namespace.this.id
    url                     = ""
    topic                   = ""
    subscription            = ""
  }
}
