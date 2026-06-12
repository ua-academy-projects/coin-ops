output "alarm_names" {
  description = "List of CPU alarm names"
  value       = [for a in aws_cloudwatch_metric_alarm.cpu : a.alarm_name]
}
