# outputs.tf

output "instance_name" {
  value = aws_db_instance.this.identifier
}

output "private_endpoint" {
  value = aws_db_instance.this.address
}

output "connection_name" {
  value = aws_db_instance.this.address
}

output "database_name" {
  value = aws_db_instance.this.db_name
}

output "database_user" {
  value = aws_db_instance.this.username
}
