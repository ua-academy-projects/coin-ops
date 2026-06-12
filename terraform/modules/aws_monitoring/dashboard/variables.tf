variable "instance_ids" {
  description = "Map of instance name to instance ID"
  type        = map(string)
}

variable "alb_arn_suffix" {
  description = "ALB ARN suffix"
  type        = string
}

variable "target_group_arn_suffix" {
  description = "Target group ARN suffix"
  type        = string
}

variable "region" {
  description = "AWS region for CloudWatch dashboard"
  type        = string
}
