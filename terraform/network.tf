resource "hyperv_network_switch" "internal" {
  name                = "coin-ops-internal"
  switch_type         = "Internal"
  allow_management_os = true
  notes               = "Internal switch for coin-ops 3-node cluster (172.31.1.0/24)"
}
