output "address" {
  description = "RDS endpoint address without port."
  value       = aws_db_instance.main.address
}

output "endpoint" {
  description = "RDS endpoint including port."
  value       = aws_db_instance.main.endpoint
}

output "port" {
  description = "RDS PostgreSQL port."
  value       = aws_db_instance.main.port
}

output "database_name" {
  description = "Application database name."
  value       = aws_db_instance.main.db_name
}

output "username" {
  description = "Application database username."
  value       = aws_db_instance.main.username
}

output "security_group_id" {
  description = "Database security group ID."
  value       = aws_security_group.database.id
}
