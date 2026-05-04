output "jump_host_public_ip" {
  description = "Public IP address of the Jump Host"
  value       = aws_instance.jump_host.public_ip
}

output "internal_vm_private_ip" {
  description = "Private IP address of the Internal VM"
  value       = aws_instance.internal_instance.private_ip
}