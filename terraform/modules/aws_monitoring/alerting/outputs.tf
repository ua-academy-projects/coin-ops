output "sns_topic_arn" {
  description = "ARN of SNS topic — used by all alarm modules"
  value       = aws_sns_topic.alerts.arn
}
