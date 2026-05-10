locals {
  iam_bindings = {
    for binding in flatten([
      for key, cfg in var.secret_access : [
        for secret in cfg.secrets : {
          key                = "${key}-${secret}"
          secret_resource_id = var.secrets[secret]
          service_account    = var.service_accounts[cfg.service_account].email
        }
      ]
    ]) : binding.key => binding
  }
}
