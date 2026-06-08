# Task: AWS Monitoring, Logging & Alerting

**Project:** CoinOps — Coin Rates Monitoring System  
**Cloud:** AWS  
**Prerequisites:** GCP infrastructure destroyed (`terraform destroy`), application migrated to AWS

---

## Context

The application currently runs on GCP. Before starting this task, destroy the GCP environment and bring the full stack up on AWS. The goal of this task is to build practical understanding of AWS-native monitoring and logging tools — **by doing it manually first**, then automating with Terraform.

---

## Phase 1: Migrate Application to AWS

- [ ] Run `terraform destroy` on the GCP environment
- [ ] Deploy the full coin-ops stack on AWS (VMs, RDS/PostgreSQL, load balancer, scaling group)
- [ ] Verify all services are running: proxy, history API, history consumer, UI, queue, DB
- [ ] Confirm the app is accessible via the AWS load balancer DNS

> **Why manual first:** You can't automate what you don't understand. Clicking through the console once teaches you what each button actually does. Terraform modules come after.

---

## Phase 2: Understand CloudWatch — Core Concepts

Before touching dashboards or alerts, explore AWS CloudWatch manually in the console.

### 2.1 What CloudWatch covers

| AWS Concept | GCP Equivalent | Purpose |
|---|---|---|
| CloudWatch Metrics | Cloud Monitoring metrics | Numeric time-series data (CPU, errors, latency) |
| CloudWatch Logs | Cloud Logging | Raw log streams from services |
| Log-Based Metrics | Log-based metrics (GCP) | Custom metrics derived from log patterns |
| CloudWatch Alarms | Alerting policies | Trigger actions when metric crosses a threshold |
| SNS (Simple Notification Service) | Notification channels | Deliver alert notifications (email, Slack, etc.) |
| CloudWatch Dashboards | Cloud Monitoring dashboards | Visual panels with graphs and widgets |

### 2.2 Standard metrics — what you get for free

AWS automatically publishes metrics for:
- **EC2:** `CPUUtilization`, `NetworkIn`, `NetworkOut`, `StatusCheckFailed`
- **ALB (Application Load Balancer):** `HTTPCode_ELB_5XX_Count`, `HTTPCode_Target_4XX_Count`, `RequestCount`, `TargetResponseTime`, `HealthyHostCount`, `UnHealthyHostCount`
- **RDS:** `CPUUtilization`, `DatabaseConnections`, `FreeStorageSpace`, `ReadLatency`, `WriteLatency`

> Read the [AWS ALB metrics docs](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/load-balancer-cloudwatch-metrics.html) — understand each metric name before adding it to a dashboard.

---

## Phase 3: Set Up S3 Bucket for Logs

AWS access logs and flow logs are stored in S3. The bucket may be created automatically by some services, but you need to understand what is stored where.

- [ ] Create an S3 bucket for logs: e.g. `coin-ops-logs-<your-name>`
- [ ] Enable **ALB access logging** → point to the S3 bucket
- [ ] Enable **VPC Flow Logs** → send to CloudWatch Logs or S3
- [ ] Browse the bucket after some traffic — understand the log format

> **Key difference from GCP:** On GCP, logs go to Cloud Logging automatically. On AWS, you explicitly enable access logging per service and choose where it lands (S3 or CloudWatch Logs). S3 is cheaper for long-term storage; CloudWatch Logs is easier to query.

---

## Phase 4: Build CloudWatch Dashboards Manually

Go to CloudWatch → Dashboards → Create dashboard. Build it with widgets, not code.

### 4.1 Dashboard: Infrastructure Overview

Add the following widgets:

| Widget | Metric | Why it matters |
|---|---|---|
| Line graph | EC2 `CPUUtilization` (all instances) | Spot hot nodes, understand baseline load |
| Line graph | ALB `RequestCount` | Traffic volume over time |
| Line graph | ALB `TargetResponseTime` | Latency — is the app slow? |
| Number widget | ALB `HealthyHostCount` | How many backends are healthy right now |
| Line graph | RDS `CPUUtilization` | DB is often the bottleneck |
| Line graph | RDS `DatabaseConnections` | Connection pool exhaustion = app crashes |

### 4.2 Dashboard: Error Tracking

| Widget | Metric | Why it matters |
|---|---|---|
| Line graph | ALB `HTTPCode_ELB_5XX_Count` | Load balancer itself is failing (config/capacity issues) |
| Line graph | ALB `HTTPCode_Target_5XX_Count` | Your app is returning 500 errors |
| Line graph | ALB `HTTPCode_Target_4XX_Count` | Bad requests (client errors, useful for debugging) |
| Number widget | EC2 `StatusCheckFailed` | VM hardware/network failure |

> **Goal:** After building these manually, you should be able to answer: *"Is the system healthy right now?"* just by looking at the dashboard.

---

## Phase 5: Create Log-Based Metrics (Custom Metrics)

Some things you want to monitor don't have a standard metric — you need to extract them from logs.

### 5.1 Concept

On GCP, these are called **log-based metrics**. On AWS, the equivalent is a **CloudWatch Metric Filter** on a Log Group.

How it works:
1. Your app writes logs to CloudWatch Logs (via CloudWatch Agent or direct SDK)
2. You create a **Metric Filter** — a pattern that matches specific log lines
3. CloudWatch increments a custom metric counter each time the pattern matches
4. You can alarm and graph this custom metric like any other

### 5.2 Example use cases for CoinOps

- Count lines matching `"level=error"` in the proxy logs → metric: `proxy_error_count`
- Count lines matching `"coin rate fetch failed"` → metric: `rate_fetch_failures`
- Count lines matching `"queue timeout"` → metric: `queue_timeouts`

### 5.3 Steps

- [ ] Install and configure **CloudWatch Agent** on your EC2 instances
- [ ] Verify logs appear in CloudWatch Logs → Log Groups
- [ ] Create a Metric Filter on the proxy log group for error lines
- [ ] Graph the resulting custom metric on your dashboard

> Read: [CloudWatch Logs Metric Filters](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/MonitoringLogData.html)

---

## Phase 6: Set Up Alarms with Intentionally Low Thresholds

The goal here is to **make the alarms fire** so you understand the full alert lifecycle. Use thresholds that will trigger during normal operation.

### 6.1 Ephemeral / learning thresholds (fire immediately)

| Alarm name | Metric | Threshold (intentionally low) | Purpose |
|---|---|---|---|
| `high-cpu-alarm` | EC2 `CPUUtilization` | > 5% for 1 minute | Fires almost immediately — test the pipeline |
| `5xx-errors-alarm` | ALB `HTTPCode_ELB_5XX_Count` | > 0 for 1 minute | Any 5xx = alert |
| `no-metrics-alarm` | Any metric | Missing data for 5 min | Detect if monitoring stops reporting |
| `unhealthy-hosts-alarm` | ALB `UnHealthyHostCount` | >= 1 | At least one backend is down |

> **Why low thresholds?** The point is to see the full flow: metric fires → alarm state changes to `ALARM` → SNS notification sent → you receive an email. Once you see it work end-to-end, raise the thresholds to sensible production values.

### 6.2 Production thresholds (set after learning)

| Alarm name | Metric | Sensible threshold |
|---|---|---|
| `high-cpu-alarm` | EC2 `CPUUtilization` | > 80% for 5 minutes |
| `5xx-errors-alarm` | ALB `HTTPCode_ELB_5XX_Count` | > 10 per minute |
| `db-connections-alarm` | RDS `DatabaseConnections` | > 80% of max connections |
| `no-healthy-hosts` | ALB `HealthyHostCount` | < 1 for 1 minute |
| `no-metrics-alarm` | Any metric | Missing for 10 minutes |

### 6.3 Wire alarms to notifications

- [ ] Create an **SNS Topic**: `coin-ops-alerts`
- [ ] Subscribe your email to it
- [ ] Confirm the subscription (check your inbox)
- [ ] Attach the SNS topic to each alarm as the action
- [ ] Trigger an alarm intentionally — verify the email arrives

---

## Phase 7: Check Alarm States

After creating alarms, observe all three states in the console:

| State | Meaning |
|---|---|
| `OK` | Metric is within the defined threshold |
| `ALARM` | Metric crossed the threshold — action triggered |
| `INSUFFICIENT_DATA` | Not enough data points yet (common right after creation) |

> `INSUFFICIENT_DATA` is normal for new alarms. It transitions to `OK` or `ALARM` once enough data points accumulate (depends on the evaluation period you set).

---

## Phase 8: Read Best Practices Articles

Before automating, read at least two articles on AWS monitoring/logging best practices. Take notes on what the articles recommend vs. what you actually set up.

Suggested reading:
- [AWS Well-Architected Framework — Reliability Pillar](https://docs.aws.amazon.com/wellarchitected/latest/reliability-pillar/welcome.html)
- [Best practices for CloudWatch alarms](https://aws.amazon.com/blogs/mt/best-practices-for-aws-cloudwatch-alarms/)
- [Centralizing logs with CloudWatch](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/CloudWatch-Logs-Monitoring-CloudTrail.html)

---

## Phase 9: Automate with Terraform

**Only after completing all manual steps above.**

- [ ] Write a Terraform module `modules/aws_monitoring` that creates:
  - S3 bucket for logs
  - CloudWatch Alarms for CPU, 5XX errors, unhealthy hosts, missing metrics
  - SNS Topic and email subscription
  - (Optional) CloudWatch Dashboard via `aws_cloudwatch_dashboard` resource with JSON widget config
- [ ] Module inputs: `alarm_email`, `alb_arn`, `instance_ids`, `rds_identifier`
- [ ] Use `aws_cloudwatch_metric_alarm` resource
- [ ] Apply, verify in console that everything matches what you built manually

> The Terraform module should reproduce exactly what you built by hand — no surprises. If you skip the manual phase, you won't know what the module should create.

---

## Deliverables

- [ ] CloudWatch Dashboard (Infrastructure + Errors) visible in AWS Console
- [ ] At least one custom metric derived from application logs
- [ ] At least 3 alarms created, wired to SNS, all transitioned to `OK` or `ALARM` (not stuck in `INSUFFICIENT_DATA`)
- [ ] Email received when an alarm fires
- [ ] S3 bucket with ALB access logs
- [ ] Terraform module that reproduces the setup
- [ ] `docs/07-aws-monitoring.md` — document what you built, what each metric means, and what problems you ran into

---

## Key AWS vs GCP Differences to Keep in Mind

| Topic | GCP | AWS |
|---|---|---|
| Logging destination | Cloud Logging (automatic) | CloudWatch Logs or S3 (must enable per service) |
| Custom metrics from logs | Log-based metrics | CloudWatch Metric Filters |
| Alerting | Alerting policies | CloudWatch Alarms + SNS |
| Notification channel | Notification channels | SNS Topic + subscription |
| Dashboard | Cloud Monitoring dashboards | CloudWatch Dashboards |
| Log storage (long term) | Cloud Storage bucket | S3 bucket |
