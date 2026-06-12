# CloudWatch Agent configuration stored in SSM Parameter Store.
# Ansible reads this config and installs agent on k3s nodes.
# Agent collects k3s pod logs and sends to CloudWatch Log Groups.
# Also collects RAM and disk metrics from each node.

resource "aws_ssm_parameter" "cloudwatch_agent_config" {
  name  = "/coinops/cloudwatch-agent-config"
  type  = "String"
  value = jsonencode({
    metrics = {
      metrics_collected = {
        mem = {
          measurement              = ["mem_used_percent"]
          metrics_collection_interval = 60
        }
        disk = {
          measurement              = ["disk_used_percent"]
          resources                = ["/"]
          metrics_collection_interval = 60
        }
      }
      append_dimensions = {
        InstanceId = "$${aws:InstanceId}"
        InstanceType = "$${aws:InstanceType}"
      }
    }
    logs = {
      logs_collected = {
        files = {
          collect_list = [
            {
              file_path        = "/var/log/pods/coinops-proxy_*/*/*.log"
              log_group_name   = "/coinops/proxy"
              log_stream_name  = "{instance_id}"
              timezone         = "UTC"
            },
            {
              file_path        = "/var/log/pods/coinops-history*_*/*/*.log"
              log_group_name   = "/coinops/history"
              log_stream_name  = "{instance_id}"
              timezone         = "UTC"
            }
          ]
        }
      }
    }
  })
  tags = { Name = "coinops-cloudwatch-agent-config" }
}