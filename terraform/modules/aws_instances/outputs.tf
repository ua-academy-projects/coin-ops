output "instance_ips" {
  value = {
    for name, vm in aws_instance.vm : name => {
      private_ip = vm.private_ip
      public_ip  = vm.public_ip
      role       = local.instances[name].role
    }
  }
}

output "instance_ids" {
  value = {
    for name, vm in aws_instance.vm : name => vm.id
  }
}

output "instance_primary_network_interface_ids" {
  value = {
    for name, vm in aws_instance.vm : name => vm.primary_network_interface_id
  }
}
