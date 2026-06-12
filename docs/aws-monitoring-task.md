# Task 5: AWS Monitoring, Logging & Alerting — CoinOps

**Project:** CoinOps — Coin Rates Monitoring System  
**Cloud:** AWS (eu-central-1)  
**Approach:** Everything automated via Terraform + Ansible — no manual console clicks in final state

---

## Overview

AWS-native monitoring for the CoinOps application running on a k3s cluster across 3 EC2 nodes behind an ALB. The goal is to observe infrastructure health (CPU, error rates, healthy hosts) and application-level errors (from pod logs) using CloudWatch — and to automate the entire setup as code.

### AWS vs GCP Concepts

| AWS | GCP Equivalent | Purpose |
|-----|---------------|---------|
| CloudWatch Metrics | Cloud Monitoring metrics | Numeric time-series (CPU, errors, latency) |
| CloudWatch Logs | Cloud Logging | Raw log streams |
| CloudWatch Metric Filters | Log-based metrics | Custom metrics from log patterns |
| CloudWatch Alarms | Alerting policies | Trigger when metric crosses threshold |
| SNS | Notification channels | Deliver alerts (email, Slack, Lambda) |
| CloudWatch Dashboards | Cloud Monitoring dashboards | Visual panels with graphs |
| S3 | Cloud Storage | Long-term log storage (ALB access logs) |
| CloudWatch Agent | Ops Agent (GCP) | Collect logs/metrics from inside EC2 |
| SSM Parameter Store | Secret Manager / runtime config | Store agent config, read by EC2 at startup |

---

## Architecture

```
k3s pod logs (/var/log/pods/coinops-proxy_*/*/*.log)
    ↓
CloudWatch Agent (installed on each k3s node via Ansible)
reads logs using IAM role attached to EC2 instance profile
    ↓
CloudWatch Log Groups
  /coinops/proxy
  /coinops/history
    ↓
Metric Filters (pattern: "ERROR" → ProxyErrorCount / HistoryErrorCount)
    ↓
CloudWatch Alarms
  coinops-proxy-errors    (ProxyErrorCount > 0)
  coinops-cpu-k3s-server-* (CPUUtilization > 80%)
  coinops-5xx-elb         (HTTPCode_ELB_5XX_Count > 0)
  coinops-5xx-target      (HTTPCode_Target_5XX_Count > 0)
  coinops-healthy-hosts   (HealthyHostCount < 2)
    ↓
SNS Topic: coinops-alerts
    ↓
Email: marta.penina.academic@gmail.com
```

---

## What Is Monitored

### Infrastructure Metrics (automatic — no agent needed)

AWS publishes these for free:

| Metric | Source | Alarm threshold |
|--------|--------|----------------|
| `CPUUtilization` | EC2 (each node) | > 80% for 5 min |
| `HTTPCode_ELB_5XX_Count` | ALB | > 0 |
| `HTTPCode_Target_5XX_Count` | ALB | > 0 |
| `TargetResponseTime` | ALB | dashboard only |
| `RequestCount` | ALB | dashboard only |
| `HealthyHostCount` | ALB Target Group | < 2 |
| `UnHealthyHostCount` | ALB Target Group | dashboard only |

### Application Metrics (via CloudWatch Agent + Metric Filters)

| Custom Metric | Log Pattern | Log Group | Alarm |
|---------------|-------------|-----------|-------|
| `ProxyErrorCount` | `ERROR` | `/coinops/proxy` | > 0 |
| `HistoryErrorCount` | `ERROR` | `/coinops/history` | dashboard only |

---

## Terraform Modules

All monitoring is automated. Structure:

```
terraform/modules/aws_monitoring/
  alerting/      — SNS Topic + email subscription
  logs/          — S3 bucket + bucket policy for ALB access logs
  iam/           — IAM Role + Instance Profile for CloudWatch Agent
  ec2_alarms/    — CPU alarms for each k3s node
  alb_alarms/    — 5XX errors + HealthyHostCount alarms
  log_metrics/   — CloudWatch Log Groups + Metric Filters + proxy alarm
  dashboard/     — CloudWatch Dashboard (5 widgets)
  agent/         — SSM Parameter Store with agent config JSON
```

### Key Resources Created

| Resource | Name |
|----------|------|
| S3 bucket | `coinops-alb-logs-penina` |
| SNS Topic | `coinops-alerts` |
| CloudWatch Dashboard | `coinops-monitoring` |
| IAM Role | `coinops-cloudwatch-agent-role` |
| IAM Instance Profile | `coinops-cloudwatch-agent-profile` |
| SSM Parameter | `/coinops/cloudwatch-agent-config` |
| Log Group | `/coinops/proxy`, `/coinops/history` |
| Metric Filter | `coinops-proxy-errors`, `coinops-history-errors` |
| Alarms | 5 alarms total |

---

## CloudWatch Agent Setup

The agent collects pod logs from each k3s node and ships them to CloudWatch Logs.

### How it works

1. **Terraform** creates IAM role with `CloudWatchAgentServerPolicy` and attaches it to EC2 via instance profile
2. **Terraform** stores agent config in SSM Parameter Store at `/coinops/cloudwatch-agent-config`
3. **Ansible** role `cloudwatch_agent` installs the agent on each node and starts it with config from SSM

### Agent Config (SSM)

```json
{
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/pods/coinops-proxy_*/*/*.log",
            "log_group_name": "/coinops/proxy",
            "log_stream_name": "{instance_id}"
          },
          {
            "file_path": "/var/log/pods/coinops-history*_*/*/*.log",
            "log_group_name": "/coinops/history",
            "log_stream_name": "{instance_id}"
          }
        ]
      }
    }
  }
}
```

### Ansible Role: `cloudwatch_agent`

Location: `ansible/roles/cloudwatch_agent/`  
Called from: `ansible/k3s-apps.yml`  
Runs on: all `k3s_server` nodes

Steps:
1. Download and install `amazon-cloudwatch-agent.deb`
2. Install AWS CLI (needed to read from SSM)
3. Fetch config from SSM Parameter Store
4. Start agent with fetched config

### Required Terraform Changes (pending)

The IAM instance profile must be attached to EC2 instances:

**`modules/aws_vm/main.tf`** — add inside `aws_instance`:
```hcl
iam_instance_profile = contains(each.value.tags, "k3s-server") ? var.iam_instance_profile : null
```

**`modules/aws_vm/variables.tf`** — add:
```hcl
variable "iam_instance_profile" {
  description = "IAM instance profile for CloudWatch Agent"
  type        = string
  default     = null
}
```

**`terraform/main.tf`** — add to `module "aws_vm"`:
```hcl
iam_instance_profile = module.aws_monitoring_iam.instance_profile_name
```

---

## Status

| Component | Status | Notes |
|-----------|--------|-------|
| S3 bucket + ALB logging | ✅ Done | Terraform |
| SNS Topic + email | ✅ Done | Terraform, email confirmed |
| CloudWatch Log Groups | ✅ Done | Terraform |
| Metric Filters | ✅ Done | Terraform |
| CloudWatch Alarms (5) | ✅ Done | Terraform |
| CloudWatch Dashboard | ✅ Done | Terraform |
| IAM Role + Instance Profile | ✅ Done | Terraform |
| SSM Parameter (agent config) | ✅ Done | Terraform |
| IAM profile → EC2 attach | ❌ Pending | Terraform change needed |
| CloudWatch Agent install | ❌ Pending | Ansible role needed |

## Remaining Work

1. **Terraform** — attach `iam_instance_profile` to k3s EC2 instances in `modules/aws_vm/main.tf`
2. **Ansible** — write `cloudwatch_agent` role and add to `k3s-apps.yml`
3. **Verify** — after agent runs, confirm logs appear in `/coinops/proxy` Log Group in CloudWatch console
