output "jump_host_external_ip" {
  description = "Public IP of the jump host"
  value       = module.vm["jump-host"].external_ip
}

output "jump_host_internal_ip" {
  description = "Private IP of the jump host"
  value       = module.vm["jump-host"].internal_ip
}

output "internal_vm_ips" {
  description = "Private IPs of internal VMs"
  value = {
    for name, vm in module.vm : name => vm.internal_ip
    if name != "jump-host"
  }
}

output "ssh_connection" {
  description = "SSH command to connect to jump host"
  value       = "ssh -p ${local.general.ssh_port} ${local.general.ops_user}@${module.vm["jump-host"].external_ip}"
}