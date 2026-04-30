# ----------------------------------------------------------------------------
# Load configuration from JSON files
# ----------------------------------------------------------------------------
locals {
  general  = jsondecode(file("${path.module}/../../../config/general.json"))
  networks = jsondecode(file("${path.module}/../../../config/networks.json"))
  firewall = jsondecode(file("${path.module}/../../../config/firewall.json"))
  vms      = jsondecode(file("${path.module}/../../../config/vms.json"))
}