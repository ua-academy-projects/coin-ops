# ═════════════════════════════════════════════════════════════════════════════
# AZURE NETWORKING
# ═════════════════════════════════════════════════════════════════════════════

resource "azurerm_resource_group" "main" {
  count    = var.cloud_provider == "azure" ? 1 : 0
  name     = "${var.vpc_name}-rg"
  location = local.region
  tags     = var.common_tags
}

resource "azurerm_virtual_network" "main" {
  count               = var.cloud_provider == "azure" ? 1 : 0
  name                = var.vpc_name
  address_space       = [var.vpc_cidr]
  location            = azurerm_resource_group.main[0].location
  resource_group_name = azurerm_resource_group.main[0].name
  tags                = var.common_tags
}

resource "azurerm_subnet" "subnets" {
  for_each             = var.cloud_provider == "azure" ? var.subnets : {}
  name                 = each.key
  resource_group_name  = azurerm_resource_group.main[0].name
  virtual_network_name = azurerm_virtual_network.main[0].name
  address_prefixes     = [each.value.cidr]
}

resource "azurerm_network_security_group" "main" {
  count               = var.cloud_provider == "azure" ? 1 : 0
  name                = "${var.vpc_name}-nsg"
  location            = azurerm_resource_group.main[0].location
  resource_group_name = azurerm_resource_group.main[0].name
  tags                = var.common_tags
}

# In Azure, Network Security Rules are attached to NSG.
resource "azurerm_network_security_rule" "rules" {
  for_each = var.cloud_provider == "azure" ? var.firewall_rules : {}

  name                        = each.key
  priority                    = 100 + index(keys(var.firewall_rules), each.key) # Simple incrementing priority
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = each.value.protocol == "all" ? "*" : (each.value.protocol == "icmp" ? "Icmp" : title(each.value.protocol))
  source_port_range           = "*"
  destination_port_range      = each.value.port == 0 ? "*" : tostring(each.value.port)
  source_address_prefix       = length(each.value.source_cidrs) > 0 ? null : "*"
  source_address_prefixes     = length(each.value.source_cidrs) > 0 ? each.value.source_cidrs : null
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.main[0].name
  network_security_group_name = azurerm_network_security_group.main[0].name
}

# Attach NSG to subnets
resource "azurerm_subnet_network_security_group_association" "subnets" {
  for_each                  = var.cloud_provider == "azure" ? var.subnets : {}
  subnet_id                 = azurerm_subnet.subnets[each.key].id
  network_security_group_id = azurerm_network_security_group.main[0].id
}
