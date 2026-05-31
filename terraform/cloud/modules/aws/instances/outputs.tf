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

output "workload_identities" {
  value = {
    for key, role in aws_iam_role.this : key => {
      type = "aws_iam_role"
      name = role.name
      arn  = role.arn
    }
  }
}

output "iam_roles" {
  value = {
    for key, role in aws_iam_role.this : key => {
      name = role.name
      arn  = role.arn
    }
  }
}

output "network_interface_ids" {
  value = { for key, instance in aws_instance.this : key => instance.primary_network_interface_id }
}
