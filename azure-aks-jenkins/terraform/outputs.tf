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
