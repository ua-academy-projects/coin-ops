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

variable "workload_identity_client_id" {
  type        = string
  description = "Client ID of the Azure managed identity federated with the Jenkins deployer service account."
}

variable "workload_identity_tenant_id" {
  type        = string
  description = "Tenant ID used by Azure Workload Identity."
}

variable "workload_identity_token_file" {
  type        = string
  description = "Projected service account token path used by Azure Workload Identity."
}

variable "workload_identity_authority_host" {
  type        = string
  description = "Azure authority host used by Azure SDK and CLI workload identity auth."
}
