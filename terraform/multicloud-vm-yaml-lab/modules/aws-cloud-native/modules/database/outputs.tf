output "database" {
  value = {
    managed  = true
    host     = aws_db_instance.this.address
    endpoint = aws_db_instance.this.endpoint
    port     = aws_db_instance.this.port
    name     = local.database.name
    user     = local.database.user
  }
}
