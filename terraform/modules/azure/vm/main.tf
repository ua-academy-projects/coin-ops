# create public ip only for bastion
resource "azurerm_public_ip" "this" {
  count               = var.public_ip ? 1 : 0
  name                = "${var.name}-public-ip"
  location            = var.location
  resource_group_name = var.resource_group
  allocation_method   = "Static"
}

# create network interface card (NIC) that connects a VM to a subnet
resource "azurerm_network_interface" "this" {
    name = "${var.name}-nic"
    resource_group_name = var.resource_group
    location = var.location

    ip_configuration {
        name = "internal"
        subnet_id = var.subnet_id
        private_ip_address_allocation = "Static"
        private_ip_address = var.private_ip
        # if public ip true - use resource block otherwise null
        public_ip_address_id = var.public_ip ? azurerm_public_ip.this[0].id : null
    }
}

resource "azurerm_linux_virtual_machine" "this" {
    name = var.name
    resource_group_name = var.resource_group
    location = var.location
    size = var.vm_size
    admin_username = var.ssh_user

    network_interface_ids = [azurerm_network_interface.this.id] # attach network interface card, vm gets network through this

    admin_ssh_key {
        username = var.ssh_user
        public_key = var.ssh_public_key
    }

    os_disk {
        caching = "ReadWrite"
        storage_account_type = "Standard_LRS"       # hdd backed, 3 copies same datacneter
    }
    # var.image Canonical:ubuntu-24_04-lts:server:latest
    source_image_reference {
        publisher = split(":", var.image)[0]
        offer = split(":", var.image)[1]
        sku = split(":", var.image)[2]
        version = split(":", var.image)[3]
    }

}