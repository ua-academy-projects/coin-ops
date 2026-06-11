locals {
  azure_location           = var.config.project.azure.location
  network_name             = "${var.config.network.name}-azure"
  rg_name                  = try(var.config.project.azure.resource_group_name, "${local.network_name}-rg")
  use_existing_rg          = try(var.config.project.azure.use_existing_resource_group, false)
  admin_user               = var.config.ssh.user
  use_managed_postgres     = try(var.config.project.azure.use_managed_postgres, false)
  monitoring_enabled       = try(var.config.project.azure.monitoring.enabled, true)
  monitoring_email         = try(var.config.project.azure.monitoring.alert_email, "val.don.ua@gmail.com")
  cpu_alert_threshold      = try(var.config.project.azure.monitoring.cpu_alert_threshold, 80)
  cpu_alert_severity       = try(var.config.project.azure.monitoring.cpu_alert_severity, 3)
  heartbeat_alert_severity = try(var.config.project.azure.monitoring.heartbeat_alert_severity, 2)
  log_retention_days       = try(var.config.project.azure.monitoring.log_retention_days, 30)
  heartbeat_window_minutes = try(var.config.project.azure.monitoring.heartbeat_window_minutes, 10)
  heartbeat_eval_frequency = try(var.config.project.azure.monitoring.heartbeat_evaluation_frequency, "PT5M")
  monitoring_identity_name = try(var.config.project.azure.monitoring.identity_name, "${local.network_name}-monitoring")
  syslog_facility_names = [
    "alert",
    "audit",
    "auth",
    "authpriv",
    "cron",
    "daemon",
    "ftp",
    "kern",
    "local0",
    "local1",
    "local2",
    "local3",
    "local4",
    "local5",
    "local6",
    "local7",
    "lpr",
    "mail",
    "mark",
    "news",
    "nopri",
    "ntp",
    "syslog",
    "user",
    "uucp",
  ]
  syslog_log_levels = [
    "Debug",
    "Info",
    "Notice",
    "Warning",
    "Error",
    "Critical",
    "Alert",
    "Emergency",
  ]
  default_vm_subnet_names = {
    bastion = "bastion"
    app     = "app"
    web     = "app"
  }
  load_balancer_vm_names = toset([
    for name, vm in var.config.vms : name if contains(try(vm.tags, []), var.config.load_balancer.target_tag)
  ])
  vm_subnet_names = {
    for name, vm in var.config.vms :
    name => coalesce(
      try(vm.azure_subnet, null),
      try(local.default_vm_subnet_names[name], null),
      vm.role == "bastion" ? "bastion" : contains(vm.tags, var.config.load_balancer.target_tag) ? "web" : "app"
    )
  }
  public_vms = {
    for name, vm in var.config.vms :
    name => vm if try(vm.external_ip, false) || contains(local.load_balancer_vm_names, name)
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
  resource_group_id       = local.use_existing_rg ? data.azurerm_resource_group.existing[0].id : azurerm_resource_group.main[0].id
}

resource "azurerm_log_analytics_workspace" "main" {
  count = local.monitoring_enabled ? 1 : 0

  name                = "${local.network_name}-logs"
  location            = local.resource_group_location
  resource_group_name = local.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = local.log_retention_days
}

resource "azurerm_user_assigned_identity" "monitoring" {
  count = local.monitoring_enabled ? 1 : 0

  name                = local.monitoring_identity_name
  location            = local.resource_group_location
  resource_group_name = local.resource_group_name
}

resource "azurerm_monitor_action_group" "main" {
  count = local.monitoring_enabled ? 1 : 0

  name                = "${local.network_name}-alerts"
  resource_group_name = local.resource_group_name
  short_name          = "coinopsaz"

  email_receiver {
    name                    = "primary-email"
    email_address           = local.monitoring_email
    use_common_alert_schema = true
  }
}

resource "azurerm_role_assignment" "monitoring_metrics_publisher" {
  count = local.monitoring_enabled ? 1 : 0

  scope                = local.resource_group_id
  role_definition_name = "Monitoring Metrics Publisher"
  principal_id         = azurerm_user_assigned_identity.monitoring[0].principal_id
}

resource "azurerm_role_assignment" "log_analytics_contributor" {
  count = local.monitoring_enabled ? 1 : 0

  scope                = azurerm_log_analytics_workspace.main[0].id
  role_definition_name = "Log Analytics Contributor"
  principal_id         = azurerm_user_assigned_identity.monitoring[0].principal_id
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

resource "azurerm_public_ip" "vms" {
  for_each = local.public_vms

  name                = "${local.network_name}-${each.key}-pip"
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
    public_ip_address_id          = try(azurerm_public_ip.vms[each.key].id, null)
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
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.monitoring[0].id]
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

resource "azurerm_virtual_machine_extension" "azure_monitor_agent" {
  for_each = local.monitoring_enabled ? azurerm_linux_virtual_machine.vms : {}

  name                       = "AzureMonitorLinuxAgent"
  virtual_machine_id         = each.value.id
  publisher                  = "Microsoft.Azure.Monitor"
  type                       = "AzureMonitorLinuxAgent"
  type_handler_version       = "1.0"
  auto_upgrade_minor_version = true
}

resource "azurerm_monitor_data_collection_rule" "linux" {
  count = local.monitoring_enabled ? 1 : 0

  name                = "${local.network_name}-dcr"
  location            = local.resource_group_location
  resource_group_name = local.resource_group_name

  destinations {
    log_analytics {
      workspace_resource_id = azurerm_log_analytics_workspace.main[0].id
      name                  = "logdest"
    }
  }

  data_flow {
    streams      = ["Microsoft-Syslog"]
    destinations = ["logdest"]
  }

  data_sources {
    syslog {
      name           = "syslogSource"
      facility_names = local.syslog_facility_names
      log_levels     = local.syslog_log_levels
      streams        = ["Microsoft-Syslog"]
    }
  }
}

resource "azurerm_monitor_data_collection_rule_association" "linux" {
  for_each = local.monitoring_enabled ? azurerm_linux_virtual_machine.vms : {}

  name                    = "${each.key}-dcr-association"
  target_resource_id      = each.value.id
  data_collection_rule_id = azurerm_monitor_data_collection_rule.linux[0].id
  depends_on              = [azurerm_virtual_machine_extension.azure_monitor_agent]
}

resource "azurerm_monitor_metric_alert" "cpu" {
  for_each = local.monitoring_enabled ? azurerm_linux_virtual_machine.vms : {}

  name                = "${each.value.name}-cpu-alert"
  resource_group_name = local.resource_group_name
  scopes              = [each.value.id]
  description         = "Alert when average CPU usage on the VM is above the configured threshold."
  severity            = local.cpu_alert_severity
  frequency           = "PT1M"
  window_size         = "PT5M"

  criteria {
    metric_namespace = "Microsoft.Compute/virtualMachines"
    metric_name      = "Percentage CPU"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = local.cpu_alert_threshold
  }

  action {
    action_group_id = azurerm_monitor_action_group.main[0].id
  }
}

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "heartbeat_missing" {
  for_each = local.monitoring_enabled ? azurerm_linux_virtual_machine.vms : {}

  name                    = "${each.value.name}-heartbeat-missing"
  location                = local.resource_group_location
  resource_group_name     = local.resource_group_name
  scopes                  = [azurerm_log_analytics_workspace.main[0].id]
  description             = "Alert when the VM stops sending Azure Monitor heartbeat data."
  severity                = local.heartbeat_alert_severity
  evaluation_frequency    = local.heartbeat_eval_frequency
  window_duration         = format("PT%dM", local.heartbeat_window_minutes)
  enabled                 = true
  auto_mitigation_enabled = true

  criteria {
    query                   = <<-QUERY
      Heartbeat
      | where Computer == "${each.value.name}"
      | where TimeGenerated > ago(${local.heartbeat_window_minutes}m)
    QUERY
    time_aggregation_method = "Count"
    operator                = "LessThan"
    threshold               = 1

    failing_periods {
      minimum_failing_periods_to_trigger_alert = 1
      number_of_evaluation_periods             = 1
    }
  }

  action {
    action_groups = [azurerm_monitor_action_group.main[0].id]
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
