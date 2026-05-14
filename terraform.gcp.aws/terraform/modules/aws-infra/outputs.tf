locals {
  bastion_name = one([for name, vm in var.config.vms : name if vm.role == "bastion"])
}

output "bastion_external_ip" {
  value = module.instance[local.bastion_name].external_ip
}

output "bastion_internal_ip" {
  value = module.instance[local.bastion_name].internal_ip
}

output "private_internal_ips" {
  value = {
    for name, vm in module.instance : name => vm.internal_ip
    if var.config.vms[name].role == "private"
  }
}

output "load_balancer_dns_name" {
  value = module.load_balancer.dns_name
}

output "load_balancer_ip_address" {
  value = module.load_balancer.ip_address
}
