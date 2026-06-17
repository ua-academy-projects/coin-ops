# ==============================================================================
# IAM Roles for Service Accounts (IRSA) for Jenkins
# ==============================================================================

data "aws_caller_identity" "current" {}

# 1. Create IAM Role for Jenkins Agent
resource "aws_iam_role" "jenkins_agent_role" {
  name = "${var.environment}-JenkinsAgentDeployRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = module.eks.oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${module.eks.oidc_provider}:sub" : "system:serviceaccount:jenkins:jenkins-agent",
            "${module.eks.oidc_provider}:aud" : "sts.amazonaws.com"
          }
        }
      }
    ]
  })
}

# 2. Attach ECR permissions to the Jenkins Agent Role
resource "aws_iam_role_policy" "jenkins_ecr_access" {
  name = "${var.environment}-JenkinsECRAccess"
  role = aws_iam_role.jenkins_agent_role.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:GetRepositoryPolicy",
          "ecr:DescribeRepositories",
          "ecr:ListImages",
          "ecr:DescribeImages",
          "ecr:BatchGetImage"
        ]
        Resource = "*"
      }
    ]
  })
}

output "jenkins_agent_role_arn" {
  value       = aws_iam_role.jenkins_agent_role.arn
  description = "Role ARN to annotate the Jenkins Agent Kubernetes ServiceAccount"
}

# ==============================================================================
# 3. Create IAM Role for External Secrets Operator
# ==============================================================================
resource "aws_iam_role" "external_secrets_role" {
  name = "${var.environment}-ExternalSecretsRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = module.eks.oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${module.eks.oidc_provider}:sub" : "system:serviceaccount:external-secrets:external-secrets",
            "${module.eks.oidc_provider}:aud" : "sts.amazonaws.com"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "external_secrets_access" {
  name = "${var.environment}-ExternalSecretsAccess"
  role = aws_iam_role.external_secrets_role.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = "*" # Restrict this to specific secret ARNs in production
      }
    ]
  })
}

# ==============================================================================
# 4. Create IAM Role for Application Pods
# ==============================================================================
resource "aws_iam_role" "coin_ops_app_role" {
  name = "${var.environment}-CoinOpsAppRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = module.eks.oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${module.eks.oidc_provider}:sub" : "system:serviceaccount:coin-ops-app:coin-ops-sa",
            "${module.eks.oidc_provider}:aud" : "sts.amazonaws.com"
          }
        }
      }
    ]
  })
}

output "coin_ops_app_role_arn" {
  value       = aws_iam_role.coin_ops_app_role.arn
  description = "Role ARN to annotate the Coin Ops App Kubernetes ServiceAccount"
}
