# CloudWatch alarms for Application Load Balancer.
# Monitors 5XX errors and healthy host count.

resource "aws_cloudwatch_metric_alarm" "elb_5xx" {
  alarm_name          = "coinops-5xx-elb"
  alarm_description   = "ALB returned 5XX errors — infrastructure problem"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_ELB_5XX_Count"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
  }

  alarm_actions = [var.sns_topic_arn]
  ok_actions    = [var.sns_topic_arn]

  tags = { Name = "coinops-5xx-elb" }
}

resource "aws_cloudwatch_metric_alarm" "target_5xx" {
  alarm_name          = "coinops-5xx-target"
  alarm_description   = "Application returned 5XX errors — app problem"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_Target_5XX_Count"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
  }

  alarm_actions = [var.sns_topic_arn]
  ok_actions    = [var.sns_topic_arn]

  tags = { Name = "coinops-5xx-target" }
}

resource "aws_cloudwatch_metric_alarm" "healthy_hosts" {
  alarm_name          = "coinops-healthy-hosts"
  alarm_description   = "Healthy host count dropped — nodes unhealthy"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HealthyHostCount"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 1
  threshold           = var.healthy_host_threshold
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching"

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
    TargetGroup  = var.target_group_arn_suffix
  }

  alarm_actions = [var.sns_topic_arn]
  ok_actions    = [var.sns_topic_arn]

  tags = { Name = "coinops-healthy-hosts" }
}
