data "aws_ssm_parameter" "image" {
  for_each = local.ssm_image_families

  name = local.mappings.image_family[each.key]
}

data "aws_secretsmanager_secret" "this" {
  for_each = var.secrets

  name = each.value.secret_id
}
