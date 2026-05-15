locals {
  backend_active_present = fileexists("${path.module}/backend.active.tf")
}

resource "terraform_data" "backend_active_guard" {
  input = local.backend_active_present

  lifecycle {
    precondition {
      condition     = local.backend_active_present
      error_message = "Missing terraform/backend.active.tf. Run terraform/bootstrap-gcp.sh or terraform/bootstrap-aws.sh before terraform plan/apply so the selected control-plane backend is explicit."
    }
  }
}
