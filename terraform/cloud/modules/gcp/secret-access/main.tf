resource "google_secret_manager_secret_iam_member" "this" {
  for_each = local.iam_bindings

  secret_id = each.value.secret_resource_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${each.value.service_account}"
}
