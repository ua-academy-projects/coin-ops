variable "aws_access_key" {
  description = "AWS access key for terraform-sa IAM user"
  type        = string
  sensitive   = true
}

variable "aws_secret_key" {
  description = "AWS secret key for terraform-sa IAM user"
  type        = string
  sensitive   = true
}