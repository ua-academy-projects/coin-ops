output "alb_dns_name" {
  value = try(aws_lb.main[0].dns_name, null)
}


output "alb_arn_suffix" {
  description = "ALB ARN suffix for CloudWatch metrics"
  value       = try(aws_lb.main[0].arn_suffix, null)
}

output "target_group_arn_suffix" {
  description = "Target group ARN suffix for CloudWatch metrics"
  value       = try(aws_lb_target_group.k3s[0].arn_suffix, null)
}
