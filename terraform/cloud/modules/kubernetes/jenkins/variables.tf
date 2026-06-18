variable "jenkins" {
  type = object({
    namespace                  = string
    release_name               = string
    chart_repository           = string
    chart_name                 = string
    service_type               = string
    admin_secret_name          = string
    admin_username             = string
    admin_password_placeholder = string
    jcasc = object({
      system_message        = string
      jenkins_url           = string
      agent_namespace       = string
      agent_service_account = string
      agent_label           = string
    })
    deploy_job = object({
      name        = string
      repo_url    = string
      branch      = string
      script_path = string
    })
  })
}

variable "azure_key_vault_name" {
  type        = string
  description = "Azure Key Vault name exposed to Jenkins jobs as a non-secret environment variable."
}
