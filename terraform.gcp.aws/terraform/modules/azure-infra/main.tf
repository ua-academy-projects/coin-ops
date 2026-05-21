locals {
  azure_location       = var.config.project.azure.location
  network_name         = "${var.config.network.name}-azure"
  rg_name              = try(var.config.project.azure.resource_group_name, "${local.network_name}-rg")
  use_existing_rg      = try(var.config.project.azure.use_existing_resource_group, false)
  admin_user           = var.config.ssh.user
  use_managed_postgres = try(var.config.project.azure.use_managed_postgres, false)
  vm_subnet_names = {
    bastion = "bastion"
    app     = "app"
    web     = "app"
  }
}

data "azurerm_resource_group" "existing" {
  count = local.use_existing_rg ? 1 : 0
  name  = local.rg_name
}

resource "azurerm_resource_group" "main" {
  count    = local.use_existing_rg ? 0 : 1
  name     = local.rg_name
  location = local.azure_location
}

locals {
  resource_group_name     = local.use_existing_rg ? data.azurerm_resource_group.existing[0].name : azurerm_resource_group.main[0].name
  resource_group_location = local.use_existing_rg ? data.azurerm_resource_group.existing[0].location : azurerm_resource_group.main[0].location
}

resource "azurerm_network_security_group" "main" {
  name                = "${local.network_name}-nsg"
  location            = local.resource_group_location
  resource_group_name = local.resource_group_name

  security_rule {
    name                       = "allow-ssh-to-bastion"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = var.config.ssh.allowed_source_cidr
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow-http-to-web"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["80", "443"]
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow-east-west-app"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["5432", "5672", "8000", "8080", "80", "443", "22"]
    source_address_prefix      = var.config.network.cidr
    destination_address_prefix = var.config.network.cidr
  }
}

resource "azurerm_virtual_network" "main" {
  name                = local.network_name
  location            = local.resource_group_location
  resource_group_name = local.resource_group_name
  address_space       = [var.config.network.cidr]
}

resource "azurerm_subnet" "subnets" {
  for_each = var.config.network.azure_subnets

  name                 = each.key
  resource_group_name  = local.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [each.value.cidr]

  dynamic "delegation" {
    for_each = each.key == "db" ? [1] : []

    content {
      name = "postgres-flexible-delegation"

      service_delegation {
        name = "Microsoft.DBforPostgreSQL/flexibleServers"
        actions = [
          "Microsoft.Network/virtualNetworks/subnets/join/action",
        ]
      }
    }
  }
}

resource "azurerm_subnet_network_security_group_association" "subnets" {
  for_each = var.config.network.azure_subnets

  subnet_id                 = azurerm_subnet.subnets[each.key].id
  network_security_group_id = azurerm_network_security_group.main.id
}

resource "azurerm_public_ip" "bastion" {
  name                = "${local.network_name}-bastion-pip"
  location            = local.resource_group_location
  resource_group_name = local.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_public_ip" "web" {
  name                = "${local.network_name}-web-pip"
  location            = local.resource_group_location
  resource_group_name = local.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_network_interface" "vms" {
  for_each = var.config.vms

  name                = "${local.network_name}-${each.key}-nic"
  location            = local.resource_group_location
  resource_group_name = local.resource_group_name

  ip_configuration {
    name                          = "primary"
    subnet_id                     = azurerm_subnet.subnets[local.vm_subnet_names[each.key]].id
    private_ip_address_allocation = "Static"
    private_ip_address            = each.value.ip
    public_ip_address_id          = each.key == "bastion" ? azurerm_public_ip.bastion.id : each.key == "web" ? azurerm_public_ip.web.id : null
  }
}

resource "azurerm_linux_virtual_machine" "vms" {
  for_each = var.config.vms

  name                            = "${local.network_name}-${each.key}"
  resource_group_name             = local.resource_group_name
  location                        = local.resource_group_location
  size                            = each.value.machine_type.azure
  admin_username                  = local.admin_user
  disable_password_authentication = true
  network_interface_ids = [
    azurerm_network_interface.vms[each.key].id,
  ]

  admin_ssh_key {
    username   = local.admin_user
    public_key = file(pathexpand(var.config.ssh.public_key_path))
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }
}

resource "azurerm_private_dns_zone" "postgres" {
  count = local.use_managed_postgres ? 1 : 0

  name                = "${local.network_name}.postgres.database.azure.com"
  resource_group_name = local.resource_group_name
}

resource "azurerm_private_dns_zone_virtual_network_link" "postgres" {
  count = local.use_managed_postgres ? 1 : 0

  name                  = "${local.network_name}-postgres-dns-link"
  resource_group_name   = local.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.postgres[0].name
  virtual_network_id    = azurerm_virtual_network.main.id
}

resource "azurerm_postgresql_flexible_server" "postgres" {
  count = local.use_managed_postgres ? 1 : 0

  name                          = "${local.network_name}-postgres"
  resource_group_name           = local.resource_group_name
  location                      = local.resource_group_location
  version                       = "16"
  delegated_subnet_id           = azurerm_subnet.subnets["db"].id
  private_dns_zone_id           = azurerm_private_dns_zone.postgres[0].id
  administrator_login           = "cognitor"
  administrator_password        = var.db_password
  public_network_access_enabled = false
  zone                          = "1"
  storage_mb                    = 32768
  sku_name                      = "B_Standard_B1ms"
  backup_retention_days         = 7

  depends_on = [
    azurerm_private_dns_zone_virtual_network_link.postgres[0],
  ]
}

resource "azurerm_postgresql_flexible_server_database" "app" {
  count = local.use_managed_postgres ? 1 : 0

  name      = "cognitor"
  server_id = azurerm_postgresql_flexible_server.postgres[0].id
  charset   = "UTF8"
  collation = "en_US.utf8"
}
