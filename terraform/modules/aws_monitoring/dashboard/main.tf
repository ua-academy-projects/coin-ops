# CloudWatch Dashboard for CoinOps monitoring.
# Shows CPU, ALB metrics, healthy hosts in one place.

resource "aws_cloudwatch_dashboard" "coinops" {
  dashboard_name = "coinops-monitoring"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        width  = 8
        height = 6
        properties = {
          title  = "CPU Utilization — k3s nodes"
          view   = "timeSeries"
          region = var.region
          period = 300
          stat   = "Average"
          metrics = [
            for name, id in var.instance_ids :
            ["AWS/EC2", "CPUUtilization", "InstanceId", id, { label = name }]
          ]
        }
      },
      {
        type   = "metric"
        width  = 8
        height = 6
        properties = {
          title  = "ALB Request Count"
          view   = "timeSeries"
          region = var.region
          period = 300
          stat   = "Sum"
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", var.alb_arn_suffix]
          ]
        }
      },
      {
        type   = "metric"
        width  = 8
        height = 6
        properties = {
          title  = "5XX Errors"
          view   = "timeSeries"
          region = var.region
          period = 300
          stat   = "Sum"
          metrics = [
            ["AWS/ApplicationELB", "HTTPCode_ELB_5XX_Count", "LoadBalancer", var.alb_arn_suffix],
            ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", var.alb_arn_suffix]
          ]
        }
      },
      {
        type   = "metric"
        width  = 8
        height = 6
        properties = {
          title  = "Target Response Time"
          view   = "timeSeries"
          region = var.region
          period = 300
          stat   = "Average"
          metrics = [
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", var.alb_arn_suffix]
          ]
        }
      },
      {
        type   = "metric"
        width  = 8
        height = 6
        properties = {
          title  = "Healthy / Unhealthy Hosts"
          view   = "timeSeries"
          region = var.region
          period = 300
          stat   = "Average"
          metrics = [
            ["AWS/ApplicationELB", "HealthyHostCount", "LoadBalancer", var.alb_arn_suffix, "TargetGroup", var.target_group_arn_suffix],
            ["AWS/ApplicationELB", "UnHealthyHostCount", "LoadBalancer", var.alb_arn_suffix, "TargetGroup", var.target_group_arn_suffix]
          ]
        }
      }
    ]
  })
}