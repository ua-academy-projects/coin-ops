output "networks" {
  description = "Created VPC networks"
  value = {
    for name, net in module.network : name => {
      network_name = net.network_name
      network_id   = net.network_id
      subnets      = net.subnet_cidrs
    }
  }
}

output "vms" {
  description = "All VM details"
  value = {
    for name, vm in module.vm : name => {
      internal_ip = vm.internal_ip
      external_ip = vm.external_ip
      zone        = vm.zone
    }
  }
}

output "jump_host_ip" {
  description = "External IP of the jump host for SSH access"
  value       = module.vm["vm-4-jump"].external_ip
}

output "ssh_command" {
  description = "SSH command to connect to jump host"
  value       = "ssh -A -i ~/.ssh/gcp_jump -p ${local.general.ssh_port} ${local.general.ssh_user}@${module.vm["vm-4-jump"].external_ip}"
}