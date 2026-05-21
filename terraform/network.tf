# NOTE: "Internal" switch type has no built-in NAT or internet access.
# For VMs to reach the internet (e.g., apt during first boot), either:
#   a) Enable ICS on the Windows host for this switch, OR
#   b) Change switch_type to "External" to bridge to a physical NIC.
# Ubuntu 24.04 cloud images include openssh-server + python3, so package_update
# may not be strictly required — consider setting it to false in user-data if
# internet access is not available.
resource "hyperv_network_switch" "internal" {
  name                = "CoinOpsSwitch"
  switch_type         = "Internal"
  allow_management_os = true
  notes               = "Internal switch for coin-ops 3-node cluster (172.31.1.0/24)"
}
