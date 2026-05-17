# ----------------------------------------------------------------------------
# Network Security Group — Azure firewall (equivalent of AWS Security Group)
# ----------------------------------------------------------------------------
resource "azurerm_network_security_group" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

# ----------------------------------------------------------------------------
# Inbound security rules
# ----------------------------------------------------------------------------
resource "azurerm_network_security_rule" "ingress" {
  for_each = { for rule in var.ingress_rules : rule.name => rule }

  name                        = each.value.name
  priority                    = each.value.priority
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = each.value.protocol
  source_port_range           = "*"
  destination_port_range      = each.value.port
  source_address_prefix       = each.value.source
  destination_address_prefix  = "*"
  description                 = each.value.description
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.this.name
}
