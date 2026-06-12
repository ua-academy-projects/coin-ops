variable "instance_ids" {
  description = "Map of instance name to instance ID"
  type        = map(string)
}

variable "sns_topic_arn" {
  description = "SNS topic ARN for notifications"
  type        = string
}

variable "cpu_threshold" {
  description = "CPU utilization threshold percent"
  type        = number
  default     = 80
}
