# data.tf

data "aws_secretsmanager_secret_version" "db_password" {
  secret_id = var.db_password_secret_id
}
