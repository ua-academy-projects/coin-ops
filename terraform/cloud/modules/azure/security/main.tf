resource "azurerm_application_security_group" "workload" {
  for_each = local.workload_application_security_groups

  name                = each.value.name
  location            = var.location
  resource_group_name = data.azurerm_resource_group.this.name
}

resource "azurerm_network_security_group" "subnet" {
  for_each = local.subnet_network_security_groups

  name                = each.value.name
  location            = var.location
  resource_group_name = data.azurerm_resource_group.this.name
}

resource "azurerm_network_security_rule" "cidr" {
  for_each = local.cidr_rules

  name                        = substr(replace(replace(replace(replace(replace(each.key, ":", "-"), "/", "-"), "?", "-"), "%", "-"), "*", "any"), 0, 80)
  resource_group_name         = data.azurerm_resource_group.this.name
  network_security_group_name = azurerm_network_security_group.subnet[local.workload_subnets[each.value.target_workload]].name
  priority                    = each.value.priority
  direction                   = each.value.direction
  access                      = each.value.access
  protocol                    = each.value.protocol
  source_port_range           = each.value.source_port
  destination_port_range      = each.value.destination_port
  source_address_prefix       = each.value.source_prefix
  destination_address_prefix  = each.value.destination_prefix
}

resource "azurerm_network_security_rule" "workload" {
  for_each = local.workload_rules

  name                                       = substr(replace(replace(replace(replace(replace(each.key, ":", "-"), "/", "-"), "?", "-"), "%", "-"), "*", "any"), 0, 80)
  resource_group_name                        = data.azurerm_resource_group.this.name
  network_security_group_name                = azurerm_network_security_group.subnet[local.workload_subnets[each.value.target_workload]].name
  priority                                   = each.value.priority
  direction                                  = each.value.direction
  access                                     = each.value.access
  protocol                                   = each.value.protocol
  source_port_range                          = each.value.source_port
  destination_port_range                     = each.value.destination_port
  source_application_security_group_ids      = [azurerm_application_security_group.workload[each.value.source_workload].id]
  destination_application_security_group_ids = [azurerm_application_security_group.workload[each.value.target_workload].id]
}

resource "azurerm_subnet_network_security_group_association" "this" {
  for_each = var.subnet_ids

  subnet_id                 = each.value
  network_security_group_id = azurerm_network_security_group.subnet[each.key].id
}
