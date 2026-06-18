resource "azurerm_kubernetes_cluster" "this" {
  name                = var.cluster.name
  location            = var.location
  resource_group_name = var.resource_group_name
  dns_prefix          = var.cluster.dns_prefix
  kubernetes_version  = var.cluster.kubernetes_version
  sku_tier            = try(var.cluster.sku_tier, "Free")

  default_node_pool {
    name            = var.cluster.node_pool.name
    vm_size         = var.cluster.node_pool.vm_size
    node_count      = var.cluster.node_pool.node_count
    os_disk_size_gb = var.cluster.node_pool.os_disk_size_gb
    vnet_subnet_id  = var.subnet_ids[var.cluster.subnet]
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin = "azure"
    network_policy = "azure"
  }
}
