output "proxy_log_group" {
  value = aws_cloudwatch_log_group.proxy.name
}

output "history_log_group" {
  value = aws_cloudwatch_log_group.history.name
}
