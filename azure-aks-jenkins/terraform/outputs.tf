output "resource_group_name" {
  value = module.resource_group.name
}

output "aks_name" {
  value = module.aks.name
}

output "acr_name" {
  value = module.acr.name
}

output "acr_login_server" {
  value = module.acr.login_server
}

output "jenkins_namespace" {
  value = module.jenkins.jenkins_namespace
}

output "app_namespace" {
  value = module.jenkins.app_namespace
}

output "jenkins_admin_username" {
  value = module.jenkins.admin_username
}

output "jenkins_admin_password" {
  value = nonsensitive(module.jenkins.admin_password)
}

output "jenkins_service_name" {
  value = module.jenkins.service_name
}

output "log_analytics_workspace_name" {
  value = module.monitoring.log_analytics_workspace_name
}

output "log_analytics_workspace_id" {
  value = module.monitoring.log_analytics_workspace_id
}

output "monitoring_action_group_id" {
  value = module.monitoring.action_group_id
}

output "monitoring_identity_name" {
  value = module.monitoring_identity.name
}

output "monitoring_identity_client_id" {
  value = module.monitoring_identity.client_id
}

output "monitoring_identity_principal_id" {
  value = module.monitoring_identity.principal_id
}
