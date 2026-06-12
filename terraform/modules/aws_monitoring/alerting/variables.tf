variable "topic_name" {
  description = "SNS topic name"
  type        = string
  default     = "coinops-alerts"
}

variable "alert_email" {
  description = "Email address for alarm notifications"
  type        = string
}
