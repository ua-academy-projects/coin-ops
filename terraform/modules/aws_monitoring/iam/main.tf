# IAM role for EC2 instances running CloudWatch Agent.
# Agent needs permission to write logs and metrics to CloudWatch.

resource "aws_iam_role" "cloudwatch_agent" {
  name = "coinops-cloudwatch-agent-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Name = "coinops-cloudwatch-agent-role" }
}

# AWS managed policy — grants full CloudWatch Agent permissions
resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  role       = aws_iam_role.cloudwatch_agent.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# SSM policy — allows agent to read config from Parameter Store
resource "aws_iam_role_policy" "cloudwatch_agent_ssm" {
  name = "coinops-cloudwatch-agent-ssm"
  role = aws_iam_role.cloudwatch_agent.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ssm:GetParameter", "ssm:GetParameters"]
      Resource = "arn:aws:ssm:*:*:parameter/coinops/*"
    }]
  })
}

# Instance profile — attaches IAM role to EC2 instance
resource "aws_iam_instance_profile" "cloudwatch_agent" {
  name = "coinops-cloudwatch-agent-profile"
  role = aws_iam_role.cloudwatch_agent.name
}