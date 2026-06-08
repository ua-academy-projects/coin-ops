output "jump_host_external_ip" {
  value = try(aws_instance.vm["jump-host"].public_ip, null)
}

output "jump_host_internal_ip" {
  value = try(aws_instance.vm["jump-host"].private_ip, null)
}

output "internal_vm_ips" {
  value = {
    for name, vm in aws_instance.vm : name => vm.private_ip
    if name != "jump-host"
  }
}

# Old output — kept for backward compatibility
output "ui_instance_id" {
  value = try(aws_instance.vm["node-03"].id, null)
}

# All k3s node IDs — used by aws_lb to register all nodes in Target Group
output "k3s_instance_ids" {
  value = {
    for name, vm in aws_instance.vm : name => vm.id
    if contains(try(var.config.vms[name].tags, []), "k3s-server")
  }
}

# k3s-server-1 public IP — entry point for SSH and kubectl
output "k3s_server_1_public_ip" {
  value = try(aws_instance.vm["k3s-server-1"].public_ip, null)
}