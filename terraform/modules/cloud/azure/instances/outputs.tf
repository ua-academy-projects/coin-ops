output "instance_ips" {
  value = {
    for name, nic in azurerm_network_interface.vm : name => {
      private_ip = nic.private_ip_address
      public_ip  = try(azurerm_public_ip.vm[name].ip_address, null)
      role       = local.instances[name].role
    }
  }
}
