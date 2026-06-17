# CodeBuild needs its own IAM role — separate from terraform-sa.
# terraform-sa is a human-facing IAM *user* with access keys; CodeBuild is
# an AWS *service* that assumes a role via sts:AssumeRole, same pattern as
# the EKS cluster/node roles. This role needs the same broad permissions
# terraform-sa has (since CodeBuild runs `terraform apply` on our behalf),
# plus CloudWatch Logs access so build output is visible in AWS Console.

resource "aws_iam_role" "codebuild" {
  name = "coinops-codebuild-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "codebuild.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Name = "coinops-codebuild-role" }
}

# CloudWatch Logs — so `terraform apply` output is visible in the build log
resource "aws_iam_role_policy" "codebuild_logs" {
  name = "coinops-codebuild-logs"
  role = aws_iam_role.codebuild.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ]
      Resource = "*"
    }]
  })
}

# S3 — CodeBuild needs to read source (if pulled via S3) and write build cache
resource "aws_iam_role_policy" "codebuild_s3" {
  name = "coinops-codebuild-s3"
  role = aws_iam_role.codebuild.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:PutObject", "s3:GetBucketLocation", "s3:ListBucket"]
      Resource = "*"
    }]
  })
}

# Terraform itself needs the same permissions terraform-sa has, since
# CodeBuild is the thing actually running `terraform apply` now.
# Reusing AdministratorAccess here would violate least-privilege, so this
# attaches the same custom policy already created for terraform-sa.
resource "aws_iam_role_policy_attachment" "codebuild_terraform_permissions" {
  role       = aws_iam_role.codebuild.name
  policy_arn = "arn:aws:iam::${var.aws_account_id}:policy/TerraformCoinOpsPolicy"
}
