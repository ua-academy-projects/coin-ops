output "instance_profile_name" {
  description = "Instance profile name — attach to EC2 instances"
  value       = aws_iam_instance_profile.cloudwatch_agent.name
}

output "role_arn" {
  description = "IAM role ARN"
  value       = aws_iam_role.cloudwatch_agent.arn
}
