resource "azurerm_servicebus_namespace" "this" {
  name                = "${var.safe_prefix}-${var.unique_suffix}-queue"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "Basic"
}

resource "azurerm_servicebus_queue" "main" {
  name         = var.runtime.queue.name
  namespace_id = azurerm_servicebus_namespace.this.id

  lock_duration                        = "PT${try(var.runtime.queue.visibility_timeout_seconds, 30)}S"
  max_delivery_count                   = try(var.runtime.queue.max_receive_count, 3)
  dead_lettering_on_message_expiration = true
}

resource "azurerm_role_assignment" "servicebus_sender" {
  for_each = var.app_instances

  scope                = azurerm_servicebus_namespace.this.id
  role_definition_name = "Azure Service Bus Data Sender"
  principal_id         = each.value.principal_id
}

resource "azurerm_role_assignment" "servicebus_receiver" {
  for_each = var.app_instances

  scope                = azurerm_servicebus_namespace.this.id
  role_definition_name = "Azure Service Bus Data Receiver"
  principal_id         = each.value.principal_id
}
