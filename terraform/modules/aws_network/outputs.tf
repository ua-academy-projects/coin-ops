output "vpc_id" {
  value = aws_vpc.vpc.id
}

output "subnet_ids" {
  value = { for name, subnet in aws_subnet.subnet : name => subnet.id }
}

output "private_subnet_ids" {
  description = "Subnet IDs for subnets without public = true (used by aws_nat_route)."
  value       = { for name in keys(local.private_subnets) : name => aws_subnet.subnet[name].id }
}
