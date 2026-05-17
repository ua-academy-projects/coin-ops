locals {
  fallback_rules = {
    "allow-ssh-external" = {
      protocols    = [{ protocol = "tcp", ports = ["22"] }]
      source_cidrs = ["0.0.0.0/0"]
      target_role  = "jump-host"
    }
  }
  rules = jsondecode(
    length(var.firewall_rules) > 0
    ? jsonencode(var.firewall_rules)
    : jsonencode(local.fallback_rules)
  )

  target_roles = toset([for _, rule in local.rules : rule.target_role])

  flat_rules = flatten([
    for rule_name, rule in local.rules : [
      for proto in rule.protocols :
      proto.protocol == "icmp"
      ? [{
        key                    = "${rule_name}-icmp"
        target_role            = rule.target_role
        protocol               = "Icmp"
        source_cidrs           = lookup(rule, "source_cidrs", null)
        source_role            = lookup(rule, "source_role", null)
        destination_port_range = "*"
        source_port_range      = "*"
      }]
      : [
        for port in lookup(proto, "ports", []) : {
          key                    = "${rule_name}-${proto.protocol}-${port}"
          target_role            = rule.target_role
          protocol               = title(lower(proto.protocol))
          source_cidrs           = lookup(rule, "source_cidrs", null)
          source_role            = lookup(rule, "source_role", null)
          destination_port_range = port
          source_port_range      = "*"
        }
      ]
    ]
  ])
  flat_rules_map = {
    for idx, rule in local.flat_rules : rule.key => merge(rule, { priority = 200 + idx })
  }
}

resource "azurerm_application_security_group" "asg" {
  for_each            = local.target_roles
  name                = "${replace(each.key, "-", "")}-asg"
  location            = var.location
  resource_group_name = var.resource_group_name
}

resource "azurerm_network_security_group" "nsg" {
  for_each            = local.target_roles
  name                = "${replace(each.key, "-", "")}-nsg"
  location            = var.location
  resource_group_name = var.resource_group_name
}

resource "azurerm_network_security_rule" "ingress" {
  for_each                    = local.flat_rules_map
  name                        = substr(replace(replace(each.key, ".", "-"), "_", "-"), 0, 80)
  priority                    = each.value.priority
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = each.value.protocol
  source_port_range           = each.value.source_port_range
  destination_port_range      = each.value.destination_port_range
  source_address_prefixes     = each.value.source_cidrs
  destination_address_prefix  = "*"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.nsg[each.value.target_role].name
  source_application_security_group_ids = each.value.source_role != null ? [
    azurerm_application_security_group.asg[each.value.source_role].id
  ] : null
}

resource "azurerm_network_security_rule" "egress" {
  for_each                    = azurerm_network_security_group.nsg
  name                        = "allow-all-egress"
  priority                    = 4090
  direction                   = "Outbound"
  access                      = "Allow"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = var.resource_group_name
  network_security_group_name = each.value.name
}
