# container for managing a network security group that contains a lit of network security rules
resource "azurerm_network_security_group" "this" {
    name = var.name
    resource_group_name = var.resource_group
    location = var.location
}

# security rules
resource "azurerm_network_security_rule" "this" {
    for_each = { for rule in var.rules : rule.name => rule }

    name = each.value.name
    resource_group_name = var.resource_group
    network_security_group_name = azurerm_network_security_group.this.name    # the name of the network Security Group that we want to attach the rule to
    priority = each.value.priority  # 1) priority 100 - allow ssh from bastion ip only 2) Deny SSH from 0.0.0.0/0 (the lower the priority number, the higher is the priority of this rule)
    direction = each.value.direction    # Inbound traffic or Outbound
    access = each.value.access  # Whether network traffic is allowed or denied (Allow / Deny)
    protocol = each.value.protocol  
    source_port_range = "*" # any source port traffic comes from
    destination_port_range = each.value.port    # which port to allow 22 for ssh 80 for http
    source_address_prefix = each.value.source   # where traffic comes from (0.0.0.0/0 for anywhere)
    destination_address_prefix = "*"    # traffic can go to any ip on the vm
}

# attach network security group (NSG) to subnet so rules apply to all vms in subnet
resource "azurerm_subnet_network_security_group_association" "this" {
    subnet_id = var.subnet_id
    network_security_group_id = azurerm_network_security_group.this.id
}