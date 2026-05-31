data "aws_secretsmanager_secret" "this" {
  for_each = var.secrets

  name = each.value.secret_id
}
