# create network
resource "azurerm_virtual_network" "this" {
    name = var.network_name
    resource_group_name = var.resource_group
    location = var.location
    address_space = [var.network_cidr] # cidr 
}

# create subnetwork
resource "azurerm_subnet" "this" {  
    name = var.subnetwork_name
    resource_group_name = var.resource_group
    virtual_network_name = azurerm_virtual_network.this.name
    address_prefixes = [var.subnetwork_cidr]

    depends_on = [azurerm_virtual_network.this] # create vpc first then subnet
}

# create public static ip for nat gateway (nic - network interface card)
resource "azurerm_public_ip" "nat" {
    name = "${var.network_name}-nat-ip"
    resource_group_name = var.resource_group
    location = var.location
    allocation_method = "Static"    # static ip
    sku = "Standard"    # type of resource that supports nat, load, balancer, zones
}

# create nat gateway
resource "azurerm_nat_gateway" "this" {
    name = "${var.network_name}-nat"
    resource_group_name = var.resource_group
    location = var.location
}

# connect nat to public ip
resource "azurerm_nat_gateway_public_ip_association" "this" {
    nat_gateway_id = azurerm_nat_gateway.this.id
    public_ip_address_id = azurerm_public_ip.nat.id
}

# connect nat to subnet
resource "azurerm_subnet_nat_gateway_association" "this" {
    nat_gateway_id = azurerm_nat_gateway.this.id
    subnet_id = azurerm_subnet.this.id
}