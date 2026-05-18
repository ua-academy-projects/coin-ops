output "lb_public_ip" {
  description = "Public IP address of Azure Load Balancer"
  value       = try(azurerm_public_ip.lb[0].ip_address, null)
}