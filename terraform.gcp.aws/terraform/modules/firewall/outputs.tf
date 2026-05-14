output "bastion_security_group_id" {
  value = try(aws_security_group.bastion[0].id, null)
}

output "private_security_group_id" {
  value = try(aws_security_group.private[0].id, null)
}

output "load_balancer_security_group_id" {
  value = try(aws_security_group.load_balancer[0].id, null)
}
