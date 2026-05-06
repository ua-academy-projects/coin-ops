output "internal_ip" {
  description = "Private IP address"
  value       = aws_instance.vm.private_ip
}

output "external_ip" {
  description = "Public IP address (null if no public IP)"
  value       = aws_instance.vm.public_ip
}

output "name" {
  description = "Instance name"
  value       = var.name
}

output "instance_id" {
  description = "AWS instance ID"
  value       = aws_instance.vm.id
}