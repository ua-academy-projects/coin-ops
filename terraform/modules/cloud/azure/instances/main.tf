locals {
  fallback_sizes = {
    micro  = "Standard_B2s"
    small  = "Standard_B2s"
    medium = "Standard_D2s_v5"
    large  = "Standard_D4s_v5"
  }
  sizes = length(var.instance_sizes) > 0 ? var.instance_sizes : local.fallback_sizes

  fallback = {
    instance_size    = "micro"
    disk_size        = 10
    subnet           = "internal"
    has_public_ip    = false
    role             = ""
    can_ip_forward   = false
    startup_script   = ""
    user_init_script = ""
    source_image_id  = ""
    source_image_reference = {
      publisher = "Debian"
      offer     = "debian-12"
      sku       = "12-gen2"
      version   = "latest"
    }
  }

  fallback_instances = { "default-vm" = {} }
  source_instances = jsondecode(
    length(var.instances) > 0
    ? jsonencode(var.instances)
    : jsonencode(local.fallback_instances)
  )

  instances = {
    for name, cfg in local.source_instances : name => merge(
      local.fallback,
      var.defaults,
      var.cloud_defaults,
      cfg
    )
  }

  instance_scripts = {
    for name, cfg in local.instances : name => join("\n\n", compact([
      cfg.user_init_script != "" ? templatefile("${path.root}/${cfg.user_init_script}", {
        username       = var.username
        ssh_public_key = var.ssh_public_key
        ssh_port       = var.ssh_port
        hostname       = "azure-${name}"
      }) : "",
      cfg.startup_script != "" ? templatefile("${path.root}/${cfg.startup_script}", {
        private_subnet_cidr = var.private_subnet_cidr
        vpc_cidr            = var.vpc_cidr
      }) : "",
    ]))
  }
}

resource "azurerm_public_ip" "vm" {
  for_each            = { for name, cfg in local.instances : name => cfg if cfg.has_public_ip }
  name                = "azure-${each.key}-pip"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_network_interface" "vm" {
  for_each              = local.instances
  name                  = "azure-${each.key}-nic"
  location              = var.location
  resource_group_name   = var.resource_group_name
  ip_forwarding_enabled = each.value.can_ip_forward

  ip_configuration {
    name                          = "primary"
    subnet_id                     = var.subnet_ids[each.value.subnet]
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = each.value.has_public_ip ? azurerm_public_ip.vm[each.key].id : null
  }
}

resource "azurerm_network_interface_security_group_association" "vm" {
  for_each                  = { for name, cfg in local.instances : name => cfg if cfg.role != "" }
  network_interface_id      = azurerm_network_interface.vm[each.key].id
  network_security_group_id = var.nsg_ids[each.value.role]
}

resource "azurerm_network_interface_application_security_group_association" "vm" {
  for_each                      = { for name, cfg in local.instances : name => cfg if cfg.role != "" }
  network_interface_id          = azurerm_network_interface.vm[each.key].id
  application_security_group_id = var.asg_ids[each.value.role]
}

resource "azurerm_linux_virtual_machine" "vm" {
  for_each                        = local.instances
  name                            = "azure-${each.key}"
  resource_group_name             = var.resource_group_name
  location                        = var.location
  size                            = try(each.value.azure_vm_size, "") != "" ? each.value.azure_vm_size : local.sizes[each.value.instance_size]
  admin_username                  = var.username
  network_interface_ids           = [azurerm_network_interface.vm[each.key].id]
  disable_password_authentication = true
  custom_data                     = local.instance_scripts[each.key] != "" ? base64encode(local.instance_scripts[each.key]) : null

  admin_ssh_key {
    username   = var.username
    public_key = var.ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    disk_size_gb         = each.value.disk_size
  }

  source_image_id = each.value.source_image_id != "" ? each.value.source_image_id : null

  dynamic "source_image_reference" {
    for_each = each.value.source_image_id == "" ? [each.value.source_image_reference] : []
    content {
      publisher = source_image_reference.value.publisher
      offer     = source_image_reference.value.offer
      sku       = source_image_reference.value.sku
      version   = source_image_reference.value.version
    }
  }

  computer_name = "azure-${each.key}"

  tags = {
    Name          = "azure-${each.key}"
    role          = each.value.role != "" ? each.value.role : "unset"
    project       = var.project_name
    cloud         = "azure"
    inventoryName = "azure-${each.key}"
  }
}
