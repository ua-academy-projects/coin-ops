variable "sns_topic_arn" {
  description = "SNS topic ARN for notifications"
  type        = string
}

variable "alb_arn_suffix" {
  description = "ALB ARN suffix (from aws_lb.arn_suffix)"
  type        = string
}

variable "target_group_arn_suffix" {
  description = "Target group ARN suffix (from aws_lb_target_group.arn_suffix)"
  type        = string
}

variable "healthy_host_threshold" {
  description = "Minimum healthy hosts before alarm"
  type        = number
  default     = 2
}
