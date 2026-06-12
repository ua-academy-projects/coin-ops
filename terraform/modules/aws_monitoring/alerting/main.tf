# SNS Topic for CloudWatch alarms.
# All alarms send notifications here → email subscribers.

resource "aws_sns_topic" "alerts" {
  name = var.topic_name
  tags = { Name = var.topic_name }
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}
