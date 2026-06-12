output "ssm_parameter_name" {
  description = "SSM parameter name with agent config — used by Ansible"
  value       = aws_ssm_parameter.cloudwatch_agent_config.name
}
