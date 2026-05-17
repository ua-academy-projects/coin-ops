locals {
  general_config  = jsondecode(file("${path.module}/../../../config/general.json"))
  networks_config = jsondecode(file("${path.module}/../../../config/networks.json"))
  firewall_config = jsondecode(file("${path.module}/../../../config/firewall.json"))
  vms_config      = jsondecode(file("${path.module}/../../../config/vms.json"))
  lookups         = jsondecode(file("${path.module}/../../../config/lookups.json"))

  general = local.general_config

  networks       = local.networks_config.networks
  subnets        = local.networks_config.subnets
  firewall_rules = local.firewall_config.firewall_rules
  # Raw VMs from config
  vms_raw = local.vms_config.vms

  # Resolve each VM's target cloud:
  #   - if the VM has a "provider" field, use it
  #   - otherwise fall back to the active var.cloud
  vms = {
    for name, vm in local.vms_raw :
    name => merge(vm, {
      resolved_provider = lookup(vm, "provider", var.cloud)
    })
    if lookup(vm, "provider", var.cloud) == var.cloud
  }

  cloud_machine_types = local.lookups.machine_types[var.cloud]
  cloud_os_images     = local.lookups.os_images[var.cloud]
  cloud_disk_types    = local.lookups.disk_types[var.cloud]

  resolved_default_machine_type = lookup(
    local.cloud_machine_types,
    local.general.default_machine_type,
    local.general.default_machine_type
  )

  resolved_default_os = lookup(
    local.cloud_os_images,
    local.general.default_os,
    local.general.default_os
  )

  resolved_default_disk_type = lookup(
    local.cloud_disk_types,
    local.general.default_disk_type,
    local.general.default_disk_type
  )

  resolved_aws_ssh_user = var.cloud == "aws" ? lookup(
    local.lookups.ssh_users.aws,
    local.general.default_os,
    "admin"
  ) : null

  aws_availability_zone = "${local.general.providers.aws.region}a"

  # Azure: resolve the SSH admin user based on the default OS
  resolved_azure_ssh_user = var.cloud == "azure" ? lookup(
    local.lookups.ssh_users.azure,
    local.general.default_os,
    "azureuser"
  ) : null

  # Azure: the single Resource Group name for all project infrastructure
  azure_resource_group_name = local.general.providers.azure.resource_group_name

  # Azure: the region for all Azure resources
  azure_location = local.general.providers.azure.location
}
