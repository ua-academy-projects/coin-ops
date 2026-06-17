# ==============================================================================
# CloudWatch Dashboard Extensions for EKS Container Insights
# ==============================================================================

data "aws_region" "current" {}

# This resource supplements the existing dashboard created in `aws.tf`
# You would typically merge this into your existing aws_cloudwatch_dashboard.main

locals {
  eks_widgets = [
    {
      type   = "metric"
      x      = 0
      y      = 18
      width  = 12
      height = 6
      properties = {
        metrics = [
          ["ContainerInsights", "pod_memory_utilization", "ClusterName", module.eks.cluster_name, "Namespace", "jenkins"]
        ]
        view    = "timeSeries"
        stacked = false
        region  = data.aws_region.current.name
        title   = "Jenkins Agents Memory Utilization (%)"
      }
    },
    {
      type   = "metric"
      x      = 12
      y      = 18
      width  = 12
      height = 6
      properties = {
        metrics = [
          ["ContainerInsights", "pod_cpu_utilization", "ClusterName", module.eks.cluster_name, "Namespace", "jenkins"]
        ]
        view    = "timeSeries"
        stacked = false
        region  = data.aws_region.current.name
        title   = "Jenkins Agents CPU Utilization (%)"
      }
    }
  ]
}

# ==============================================================================
# CloudWatch Alarms for Jenkins Agents
# ==============================================================================
resource "aws_cloudwatch_metric_alarm" "jenkins_high_memory" {
  alarm_name          = "${var.environment}-Jenkins-Agent-High-Memory"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "pod_memory_utilization"
  namespace           = "ContainerInsights"
  period              = 300
  statistic           = "Average"
  threshold           = 85 # Alert if memory exceeds 85%

  dimensions = {
    ClusterName = module.eks.cluster_name
    Namespace   = "jenkins"
  }

  alarm_description = "Alerts when Jenkins agents consume too much memory"
  # alarm_actions     = [aws_sns_topic.alerts[0].arn] # Assuming SNS topic exists
}
