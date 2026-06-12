# CoinOps — Cloud Deployment

Personal cloud deployment branch: `dev-penina-cloud`
Owner: Marta Penina (@MartaPenina)
Based on: `dev` branch of [ua-academy-projects/coin-ops](https://github.com/ua-academy-projects/coin-ops)

---

## Current Status (June 2026)

**Cloud: AWS (eu-central-1)** — fully migrated from GCP.

| Component | Status |
|-----------|--------|
| AWS Infrastructure (VPC, subnets, security groups) | ✅ Running |
| k3s cluster (3 nodes) | ✅ Running |
| CoinOps application (all services) | ✅ Running |
| CloudWatch monitoring | ✅ Running |
| ALB + Cloudflare DNS | ✅ Running |
| CloudWatch Agent (log collection) | ✅ Running on all 3 nodes |

**Live URL:** https://coinops-softserve-penina.pp.ua

---

## What This Branch Does

Deploys the CoinOps application to a k3s Kubernetes cluster on AWS using:
- **Terraform** — provisions AWS infrastructure (VMs, VPC, ALB, security groups, CloudWatch monitoring)
- **Ansible** — configures VMs, installs k3s cluster, deploys infrastructure apps, installs CloudWatch Agent
- **Helm** — deploys CoinOps application stack with per-service namespace isolation
- **k3s** — lightweight Kubernetes cluster on AWS (3 nodes, all control plane + worker)
- **CNPG (CloudNativePG)** — PostgreSQL running inside k3s cluster
- **cert-manager** — automatic TLS certificates via Let's Encrypt
- **Traefik** — Ingress controller (built into k3s)
- **Cloudflare** — DNS management
- **AWS ALB** — Application Load Balancer for k3s cluster
- **CloudWatch** — AWS-native monitoring, logging, alerting

---

## Application URLs

| Service | URL | Access |
|---------|-----|--------|
| CoinOps | https://coinops-softserve-penina.pp.ua | Public ✅ |
| Homepage | https://k3s.coinops-softserve-penina.pp.ua | Public ✅ |
| Headlamp | http://localhost:8080 | Port-forward only |
| CloudWatch Dashboard | AWS Console → CloudWatch → Dashboards → coinops-monitoring | AWS Console |

---

## Architecture

```
Internet
  │
  ▼
Cloudflare DNS (CNAME → ALB)
  │
  ▼
AWS ALB coinops-alb-589903677.eu-central-1.elb.amazonaws.com
  │
  ├── port 80  → k3s nodes → Traefik → HTTP routes
  └── port 443 → k3s nodes → Traefik → HTTPS routes
                                  │
                        ┌─────────┴──────────┐
                        ▼                    ▼
              coinops-softserve-        k3s.coinops-
               penina.pp.ua             softserve-penina.pp.ua

AWS k3s Cluster (eu-central-1):
  k3s-server-1  control plane + worker  18.196.82.182 (public) / 10.0.1.78 (private)
  k3s-server-2  control plane + worker  10.0.2.8 (private)
  k3s-server-3  control plane + worker  10.0.4.227 (private)

Monitoring:
  k3s pod logs → CloudWatch Agent → CloudWatch Logs → Metric Filters → Alarms → SNS → Email
  EC2/ALB metrics → CloudWatch Alarms → SNS → Email
```

---

## AWS Infrastructure

| Resource | Zone | Role | Public IP | Private IP |
|----------|------|------|-----------|------------|
| k3s-server-1 | eu-central-1a | control plane + worker | 18.196.82.182 | 10.0.1.78 |
| k3s-server-2 | eu-central-1a | control plane + worker | — | 10.0.2.8 |
| k3s-server-3 | eu-central-1b | control plane + worker | — | 10.0.4.227 |
| ALB | eu-central-1 | Application Load Balancer | coinops-alb-589903677... | — |

---

## AWS Monitoring (CloudWatch)

All monitoring is automated via Terraform module `terraform/modules/aws_monitoring/`.

### What is monitored

| Metric | Source | Alarm threshold | Action |
|--------|--------|----------------|--------|
| `CPUUtilization` | EC2 (each node) | > 80% for 5 min | Email via SNS |
| `HTTPCode_ELB_5XX_Count` | ALB | > 0 | Email via SNS |
| `HTTPCode_Target_5XX_Count` | ALB | > 0 | Email via SNS |
| `HealthyHostCount` | ALB Target Group | < 2 | Email via SNS |
| `ProxyErrorCount` | CloudWatch Logs (custom) | > 0 | Email via SNS |

### CloudWatch Resources

| Resource | Name | Purpose |
|----------|------|---------|
| SNS Topic | `coinops-alerts` | Alert delivery channel |
| S3 Bucket | `coinops-alb-logs-penina` | ALB access logs storage |
| IAM Role | `coinops-cloudwatch-agent-role` | EC2 permission to write logs |
| SSM Parameter | `/coinops/cloudwatch-agent-config` | Agent config storage |
| Log Group | `/coinops/proxy` | Proxy service logs |
| Log Group | `/coinops/history` | History service logs |
| Metric Filter | `coinops-proxy-errors` | Counts ERROR lines in proxy logs |
| Metric Filter | `coinops-history-errors` | Counts ERROR lines in history logs |
| Dashboard | `coinops-monitoring` | 5 widgets: CPU, RequestCount, 5XX, ResponseTime, HealthyHosts |
| Alarms | 5 total | CPU x3, ELB 5XX, Target 5XX, HealthyHosts, ProxyErrors |

### Log collection flow

```
Pod writes ERROR to stdout
    ↓ k3s saves to /var/log/pods/
    ↓ CloudWatch Agent reads file (IAM role grants access)
    ↓ sends to /coinops/proxy Log Group
    ↓ Metric Filter counts ERROR lines → ProxyErrorCount metric
    ↓ CloudWatch Alarm: ProxyErrorCount > 0
    ↓ SNS Topic coinops-alerts
    ↓ Email: marta.penina.academic@gmail.com
```

---

## Terraform Modules

```
terraform/
  main.tf                          — root module, wires all modules together
  config.yaml                      — infrastructure config (VM sizes, zones, cloud)
  modules/
    aws_network/                   — VPC, subnets, NAT gateway, route tables
    aws_security/                  — security groups (k3s, ALB, jump-host, internal)
    aws_vm/                        — EC2 instances + key pair + IAM profile attach
    aws_lb/                        — ALB + target group + listeners + attachments
    aws_monitoring/
      alerting/                    — SNS Topic + email subscription
      logs/                        — S3 bucket + bucket policy for ALB logs
      iam/                         — IAM Role + Instance Profile + SSM policy
      ec2_alarms/                  — CPU alarms for each k3s node
      alb_alarms/                  — 5XX errors + HealthyHostCount alarms
      log_metrics/                 — Log Groups + Metric Filters + proxy alarm
      dashboard/                   — CloudWatch Dashboard (5 widgets)
      agent/                       — SSM Parameter with agent config JSON
```

### Key Terraform decisions

**IAM Instance Profile** — attached to all EC2 instances via `iam_instance_profile = var.iam_instance_profile` in `modules/aws_vm/main.tf`. This allows CloudWatch Agent to authenticate without hardcoded credentials.

**SSM Parameter Store** — agent config stored at `/coinops/cloudwatch-agent-config`. Agent reads it at startup. Decouples config from code.

**Least-privilege IAM** — `terraform-sa` user has `TerraformCoinOpsPolicy` with only required permissions. Bootstrap script in `bootstrap/aws/bootstrap.sh` creates and updates this policy.

---

## Ansible Roles

| Role | Purpose |
|------|---------|
| `common` | UFW firewall, apt packages, timezone |
| `k3s_prereqs` | curl, Helm, pip3, python kubernetes library |
| `k3s_server` | initializes cluster on node-1, joins node-2 and node-3 |
| `k3s_postcheck` | verifies all nodes Ready, downloads kubeconfig |
| `cert_manager` | installs cert-manager + Let's Encrypt ClusterIssuer |
| `k3s_headlamp` | installs Headlamp UI + ServiceAccount |
| `k3s_homepage` | installs Homepage dashboard + Ingress + TLS |
| `k3s_cnpg` | installs CNPG operator only (cluster managed by Helm) |
| `cloudwatch_agent` | installs agent, reads config from SSM, starts agent |

---

## Deployment — How It Works

### 0. Bootstrap (one time only)
```bash
# In AWS CloudShell — creates terraform-sa IAM user with least-privilege policy
curl -s https://raw.githubusercontent.com/ua-academy-projects/coin-ops/dev-penina-cloud/bootstrap/aws/bootstrap.sh | bash
```

### 1. Infrastructure (Terraform)
```bash
cd terraform
export AWS_ACCESS_KEY_ID="..."
export AWS_SECRET_ACCESS_KEY="..."
export AWS_DEFAULT_REGION="eu-central-1"
terraform init
terraform apply -auto-approve
```

### 2. k3s Cluster (Ansible)
```bash
# SSH to k3s-server-1
eval $(ssh-agent -s)
ssh-add /d/.ssh/id_ed25519_devops
ssh -A -p 9922 marta_ops@18.196.82.182

# Clone repo and run
git clone https://github.com/ua-academy-projects/coin-ops.git
cd coin-ops && git checkout dev-penina-cloud
sudo apt install -y ansible
ansible-playbook -i ansible/inventory ansible/k3s-cluster.yml
```

### 3. Infrastructure Apps (Ansible)
```bash
ansible-playbook -i ansible/inventory ansible/k3s-apps.yml
# Installs: cert-manager, Headlamp, Homepage, CNPG operator, CloudWatch Agent
```

### 4. CoinOps Application (Helm)
```bash
source .env
sudo KUBECONFIG=/etc/rancher/k3s/k3s.yaml helm upgrade --install coinops helm/coinops \
  --create-namespace \
  --set secrets.dbPassword="$DB_PASSWORD" \
  --set secrets.rabbitmqPassword="$RABBITMQ_PASSWORD" \
  --set secrets.ghcrUsername="$GHCR_USERNAME" \
  --set secrets.ghcrToken="$GHCR_TOKEN" \
  --set database.host="coinops-db-rw.coinops-db.svc.cluster.local"
```

---

## What to Show / Test in AWS Console

### CloudWatch Dashboard
**AWS Console → CloudWatch → Dashboards → coinops-monitoring**
- 5 widgets: CPU utilization per node, ALB request count, 5XX errors, response time, healthy hosts
- Shows live metrics from all 3 EC2 nodes and ALB

### CloudWatch Alarms
**AWS Console → CloudWatch → Alarms**
- 5 alarms: `coinops-cpu-k3s-server-1/2/3`, `coinops-5xx-elb`, `coinops-5xx-target`, `coinops-healthy-hosts`, `coinops-proxy-errors`
- States: OK / ALARM / INSUFFICIENT_DATA

### CloudWatch Log Groups
**AWS Console → CloudWatch → Log Groups**
- `/coinops/proxy` — proxy service logs from all nodes
- `/coinops/history` — history service logs from all nodes
- Logs appear after application generates traffic

### SNS Topic
**AWS Console → SNS → Topics → coinops-alerts**
- Email subscription to marta.penina.academic@gmail.com
- Receives alert when any alarm fires

### EC2 Instances
**AWS Console → EC2 → Instances**
- 3 running instances: k3s-server-1, k3s-server-2, k3s-server-3
- Security tab → IAM role: `coinops-cloudwatch-agent-role`

### ALB
**AWS Console → EC2 → Load Balancers → coinops-alb**
- Target group `coinops-k3s` → all 3 instances healthy
- Monitoring tab → request count, response time, error rates

### S3 Bucket
**AWS Console → S3 → coinops-alb-logs-penina**
- ALB access logs — one file per 5 minutes of traffic

---

## Kubernetes Namespaces

| Namespace | Service | Purpose |
|-----------|---------|---------|
| `coinops-rabbitmq` | RabbitMQ | Message queue |
| `coinops-redis` | Redis | Cache layer |
| `coinops-proxy` | Go proxy | Central API hub |
| `coinops-history-api` | Python history API | Serves historical data |
| `coinops-history-consumer` | Python worker | Consumes queue, writes to DB |
| `coinops-ui` | React + nginx | Frontend |
| `coinops-db` | CNPG PostgreSQL | In-cluster database |
| `coinops-gateway` | Gateway | Ingress gateway |
| `cert-manager` | cert-manager | TLS automation |
| `homepage` | Homepage | Cluster dashboard |
| `headlamp` | Headlamp | Kubernetes UI |
| `cnpg-system` | CNPG operator | CloudNativePG operator |

---

## Problems & Solutions

**Problem 1 — GCP to AWS migration**
Full infrastructure rewrite from GCP (VMs, Cloud SQL, NLB) to AWS (EC2, CNPG, ALB).
Fix: new Terraform modules for AWS, keeping GCP modules intact for reference.

**Problem 2 — Terraform for_each unknown values**
`for_each` on EC2 instance IDs failed because IDs are unknown until apply.
Fix: create EC2 first with `-target`, then apply full configuration.

**Problem 3 — CloudWatch Agent NoCredentials**
Agent reported `NoCredentials` — IAM profile existed but was not attached to EC2.
Fix: added `iam_instance_profile = var.iam_instance_profile` to `aws_instance` resource, forced node replacement with `terraform apply -replace`.

**Problem 4 — SSM AccessDeniedException**
Agent could not read config from SSM — `CloudWatchAgentServerPolicy` does not include SSM permissions.
Fix: added inline policy `aws_iam_role_policy` with `ssm:GetParameter` for `/coinops/*` resources.

**Problem 5 — Helm vs Ansible ownership conflict**
Ansible created `coinops-db` namespace and CNPG Cluster without Helm labels → Helm refused to manage them.
Fix: added Helm ownership labels/annotations manually. Long-term fix: `k3s_cnpg` role now only installs operator, cluster is managed by Helm chart.

---

## Secrets — Never Commit

| File | Contains | Gitignored |
|------|---------|-----------|
| `.env` | DB_PASSWORD, RABBITMQ_PASSWORD, GHCR_TOKEN, GHCR_USERNAME | ✓ |
| `terraform/terraform.tfvars` | AWS credentials, db_password, ssh_public_key_path | ✓ |
| `bootstrap/aws/bootstrap.sh` | Creates terraform-sa (run from CloudShell, not committed with keys) | — |

---

## Next Steps

- [ ] **Verify CloudWatch logs** — confirm `/coinops/proxy` and `/coinops/history` receive logs after traffic
- [ ] **Fix k3s_cnpg role** — already updated locally, push to repo
- [ ] **ArgoCD / GitOps** — replace manual helm upgrade with GitOps-based CD
- [ ] **Cloudflare Tunnel** — replace public ALB with zero-trust tunnel
