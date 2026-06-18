output "id" {
  value = azurerm_kubernetes_cluster.dev.id
}

output "name" {
  value = azurerm_kubernetes_cluster.dev.name
}

output "host" {
  value = azurerm_kubernetes_cluster.dev.kube_config[0].host
}

output "client_certificate" {
  value     = azurerm_kubernetes_cluster.dev.kube_config[0].client_certificate
  sensitive = true
}

output "client_key" {
  value     = azurerm_kubernetes_cluster.dev.kube_config[0].client_key
  sensitive = true
}

output "cluster_ca_certificate" {
  value     = azurerm_kubernetes_cluster.dev.kube_config[0].cluster_ca_certificate
  sensitive = true
}

output "kubelet_object_id" {
  value = azurerm_kubernetes_cluster.dev.kubelet_identity[0].object_id
}
