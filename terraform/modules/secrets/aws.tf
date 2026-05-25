resource "aws_secretsmanager_secret" "app_secrets" {
  count = var.cloud_provider == "aws" ? 1 : 0

  name        = "coinops/production/app-secrets"
  description = "Sensitive application credentials for Coin Ops"

  tags = var.common_tags
}

resource "aws_secretsmanager_secret_version" "app_secrets_version" {
  count = var.cloud_provider == "aws" ? 1 : 0

  secret_id = aws_secretsmanager_secret.app_secrets[0].id
  secret_string = jsonencode({
    DATABASE_URL      = "postgresql://${var.db_username}:${var.db_password}@${var.db_host}:5432/${var.db_name}"
    DB_PASSWORD       = var.db_password
    DB_HOST           = var.db_host
    RABBITMQ_PASSWORD = var.rabbitmq_password
  })
}
