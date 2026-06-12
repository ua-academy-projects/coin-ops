# CloudWatch Agent configuration stored in SSM Parameter Store.
# Ansible reads this config and installs agent on k3s nodes.
# Agent collects k3s pod logs and sends to CloudWatch Log Groups.

resource "aws_ssm_parameter" "cloudwatch_agent_config" {
  name  = "/coinops/cloudwatch-agent-config"
  type  = "String"
  value = jsonencode({
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
