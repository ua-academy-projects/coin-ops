# outputs.tf

output "instance_names" {
  value = { for key, instance in aws_instance.this : key => instance.tags.Name }
}


output "private_ips" {
  value = { for key, instance in aws_instance.this : key => instance.private_ip }
}


output "public_ips" {
  value = { for key, instance in aws_instance.this : key => try(instance.public_ip, null) }
}


output "workload_tags" {
  value = { for key, instance in local.instances : key => instance.tags }
}
