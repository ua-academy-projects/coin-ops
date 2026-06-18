resource "aws_iam_role" "jenkins" {
  name = "coinops-jenkins-irsa-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.eks.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${replace(var.oidc_issuer_url, "https://", "")}:sub" = "system:serviceaccount:jenkins:jenkins"
          "${replace(var.oidc_issuer_url, "https://", "")}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = { Name = "coinops-jenkins-irsa-role" }
}

resource "aws_iam_role_policy" "jenkins_ssm_read" {
  name = "coinops-jenkins-ssm-read"
  role = aws_iam_role.jenkins.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ssm:GetParameter", "ssm:GetParameters"]
      Resource = "arn:aws:ssm:*:*:parameter/coinops/jenkins/*"
    }]
  })
}
