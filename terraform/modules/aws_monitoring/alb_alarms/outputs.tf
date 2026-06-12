output "alarm_names" {
  value = [
    aws_cloudwatch_metric_alarm.elb_5xx.alarm_name,
    aws_cloudwatch_metric_alarm.target_5xx.alarm_name,
    aws_cloudwatch_metric_alarm.healthy_hosts.alarm_name,
  ]
}
