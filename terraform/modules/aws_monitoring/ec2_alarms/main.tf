# CloudWatch alarms for EC2 instances (k3s nodes).
# Monitors CPU utilization — alerts when threshold exceeded.

resource "aws_cloudwatch_metric_alarm" "cpu" {
  for_each = var.instance_ids

  alarm_name          = "coinops-cpu-${each.key}"
  alarm_description   = "CPU utilization > ${var.cpu_threshold}% on ${each.key}"
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 1
  threshold           = var.cpu_threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    InstanceId = each.value
  }

  alarm_actions = [var.sns_topic_arn]
  ok_actions    = [var.sns_topic_arn]

  tags = { Name = "coinops-cpu-${each.key}" }
}
