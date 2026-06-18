variable "aws_account_id" {
  type = string
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "ssh_public_key_content" {
  type      = string
  sensitive = true
}

variable "github_repo_url" {
  description = "HTTPS URL of the GitHub repo CodeBuild pulls source from"
  type        = string
  default     = "https://github.com/ua-academy-projects/coin-ops.git"
}

variable "github_branch" {
  description = "Branch CodeBuild builds from"
  type        = string
  default     = "dev-penina-cloud"
}

# The CodeBuild project itself — defined here as Terraform, not clicked
# together in the AWS Console. This is the actual "CI entry point" from
# the task: instead of running `terraform apply` from a laptop, this
# project runs it inside an AWS-managed ephemeral container.
resource "aws_codebuild_project" "terraform_apply" {
  name         = "coinops-terraform-apply"
  description  = "Runs terraform init/apply for the CoinOps EKS infrastructure"
  service_role = aws_iam_role.codebuild.arn

  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    compute_type    = "BUILD_GENERAL1_SMALL"
    image           = "aws/codebuild/standard:7.0"
    type            = "LINUX_CONTAINER"
    privileged_mode = false

    environment_variable {
      name  = "TF_VAR_db_password"
      value = var.db_password
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "SSH_PUBLIC_KEY_CONTENT"
      value = var.ssh_public_key_content
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "TF_VAR_cloudflare_api_token"
      value = var.cloudflare_api_token
      type  = "PLAINTEXT"
    }
    environment_variable {
      name  = "TF_VAR_github_token"
      value = var.github_token
      type  = "PLAINTEXT"
    }
  }

  source {
    type            = "GITHUB"
    location        = var.github_repo_url
    buildspec       = "buildspec.yml"
    git_clone_depth = 1
  }

  source_version = var.github_branch

  tags = { Name = "coinops-terraform-apply" }
}
