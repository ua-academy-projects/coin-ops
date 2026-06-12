# CloudWatch Log Groups for CoinOps services.
# CloudWatch Agent sends pod logs here.
# Metric Filters count ERROR occurrences → custom metrics → alarms.

resource "aws_cloudwatch_log_group" "proxy" {
  name              = "/coinops/proxy"
  retention_in_days = 7
  tags              = { Name = "coinops-proxy-logs" }
}

resource "aws_cloudwatch_log_group" "history" {
  name              = "/coinops/history"
  retention_in_days = 7
  tags              = { Name = "coinops-history-logs" }
}

# Metric Filter — counts ERROR lines in proxy logs
resource "aws_cloudwatch_log_metric_filter" "proxy_errors" {
  name           = "coinops-proxy-errors"
  log_group_name = aws_cloudwatch_log_group.proxy.name
  pattern        = "ERROR"

  metric_transformation {
    name      = "ProxyErrorCount"
    namespace = "CoinOps/Application"
    value     = "1"
    default_value = "0"
  }
}

# Metric Filter — counts ERROR lines in history logs
resource "aws_cloudwatch_log_metric_filter" "history_errors" {
  name           = "coinops-history-errors"
  log_group_name = aws_cloudwatch_log_group.history.name
  pattern        = "ERROR"

  metric_transformation {
    name      = "HistoryErrorCount"
    namespace = "CoinOps/Application"
    value     = "1"
    default_value = "0"
  }
}

# Alarm on proxy errors
resource "aws_cloudwatch_metric_alarm" "proxy_errors" {
  alarm_name          = "coinops-proxy-errors"
  alarm_description   = "Proxy service logged errors"
  namespace           = "CoinOps/Application"
  metric_name         = "ProxyErrorCount"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  alarm_actions = [var.sns_topic_arn]
  ok_actions    = [var.sns_topic_arn]

  tags = { Name = "coinops-proxy-errors" }
}
