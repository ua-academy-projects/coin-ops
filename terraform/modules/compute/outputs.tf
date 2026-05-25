# =============================================================================
# modules/compute/outputs.tf
# =============================================================================
# Cloud-agnostic outputs — same interface regardless of provider.
# =============================================================================

output "instance_ips" {
  description = "Map of instance name → internal/private IP"
  value = (
    var.cloud_provider == "gcp"
    ? { for name, inst in google_compute_instance.this : name => inst.network_interface[0].network_ip }
    : (var.cloud_provider == "aws"
      ? { for name, inst in aws_instance.this : name => inst.private_ip }
    : { for name, inst in azurerm_linux_virtual_machine.this : name => inst.private_ip_address })
  )
}

output "instance_external_ips" {
  description = "Map of instance name → external/public IP (only VMs with public_ip = true)"
  value = (
    var.cloud_provider == "gcp"
    ? {
      for name, inst in google_compute_instance.this :
      name => try(inst.network_interface[0].access_config[0].nat_ip, null)
      if length(try(inst.network_interface[0].access_config, [])) > 0
    }
    : (var.cloud_provider == "aws"
      ? {
        for name, inst in aws_instance.this :
        name => inst.public_ip
        if inst.public_ip != "" && inst.public_ip != null
      }
      : {
        for name, pip in azurerm_public_ip.this :
        name => pip.ip_address
    })
  )
}

output "instance_names" {
  description = "List of all instance names"
  value = (
    var.cloud_provider == "gcp"
    ? [for inst in google_compute_instance.this : inst.name]
    : (var.cloud_provider == "aws"
      ? [for inst in aws_instance.this : inst.tags["Name"]]
    : [for inst in azurerm_linux_virtual_machine.this : inst.name])
  )
}

output "instance_ids" {
  description = "Map of instance name → ID"
  value = (
    var.cloud_provider == "gcp"
    ? { for name, inst in google_compute_instance.this : name => inst.id }
    : (var.cloud_provider == "aws"
      ? { for name, inst in aws_instance.this : name => inst.id }
    : { for name, inst in azurerm_linux_virtual_machine.this : name => azurerm_network_interface.this[name].id })
  )
}

output "instance_self_links" {
  description = "Map of instance name → self_link (GCP only)"
  value = (
    var.cloud_provider == "gcp"
    ? { for name, inst in google_compute_instance.this : name => inst.self_link }
    : {}
  )
}
