output "db_subnet_group_name" {
  value = try(aws_db_subnet_group.postgres[0].name, null)
}

output "endpoint" {
  value = try(aws_db_instance.postgres[0].address, null)
}
