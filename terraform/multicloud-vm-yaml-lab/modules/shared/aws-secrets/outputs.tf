output "refs" {
  value = {
    for key, secret in aws_secretsmanager_secret.this : key => {
      provider  = "aws"
      name      = secret.name
      arn       = secret.arn
      secret_id = secret.name
      id        = secret.id
    }
  }
}
