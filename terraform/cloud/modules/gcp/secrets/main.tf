resource "google_secret_manager_secret" "this" {
  for_each = var.secrets

  secret_id = each.value.secret_id

  replication {
    auto {}
  }
}

locals {
  iam_bindings = {
    for binding in flatten([
      for key, cfg in var.secret_access : [
        for secret in cfg.secrets : {
          key                = "${key}-${secret}"
          secret_resource_id = google_secret_manager_secret.this[secret].id
          service_account    = var.service_accounts[cfg.service_account].email
        }
      ]
    ]) : binding.key => binding
  }
}

resource "google_secret_manager_secret_iam_member" "this" {
  for_each = local.iam_bindings

  secret_id = each.value.secret_resource_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${each.value.service_account}"
}
