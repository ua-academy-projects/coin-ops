output "oidc_provider_arn" {
  description = "ARN of the registered OIDC provider — referenced by every IRSA role's trust policy"
  value       = aws_iam_openid_connect_provider.eks.arn
}

output "oidc_provider_url" {
  description = "OIDC issuer URL without the https:// prefix — IAM trust policies need this exact format"
  value       = replace(var.oidc_issuer_url, "https://", "")
}

output "jenkins_role_arn" {
  description = "ARN of the Jenkins IRSA role — referenced in values.yaml's serviceAccount.annotations"
  value       = aws_iam_role.jenkins.arn
}