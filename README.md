# CoinOps — Cloud Deployment (EKS + CodeBuild + Jenkins)

Personal cloud deployment branch: `dev-penina-cloud`
Owner: Marta Penina (@MartaPenina)
Based on: `dev` branch of [ua-academy-projects/coin-ops](https://github.com/ua-academy-projects/coin-ops)

---

## Current Status (June 2026)

**Cloud: AWS (eu-central-1)** — EKS-based deployment with full CI/CD pipeline.

| Component | Status |
|-----------|--------|
| AWS Infrastructure (VPC, subnets, security groups, ALB, RDS) | ✅ Running |
| EKS Cluster (2 managed nodes) | ✅ Running |
| AWS CodeBuild (CI/CD trigger) | ✅ Running |
| Jenkins on EKS (Helm + JCasC) | ✅ Running |
| CNPG PostgreSQL on EKS | ✅ Running |
| CoinOps application (all services on EKS) | ✅ Running |
| CloudWatch monitoring | ✅ Running |
| Cloudflare Tunnel (Jenkins + App) | ✅ Running |

**Live URLs:**
- App: https://coinops-softserve-penina.pp.ua
- Jenkins: https://jenkins.coinops-softserve-penina.pp.ua

---

## What This Branch Does

Full automated CI/CD pipeline:

```
git push → AWS CodeBuild
         → terraform apply (EKS + Jenkins via Helm + JCasC)
         → Jenkins accessible at jenkins.coinops-softserve-penina.pp.ua
         → Jenkins pipeline → Ansible → CoinOps deployed to EKS
         → App accessible at coinops-softserve-penina.pp.ua
```

**Technologies used:**
- **AWS CodeBuild** — triggers terraform apply on every push
- **Terraform** — provisions EKS, IAM, RDS, ALB, CloudWatch, CodeBuild, Jenkins via Helm
- **AWS EKS** — managed Kubernetes cluster (2 worker nodes, v1.31)
- **Jenkins** — installed via Helm with JCasC (Configuration as Code), job created automatically
- **Ansible** — deploys CoinOps application stack to EKS from Jenkins pipeline
- **CNPG (CloudNativePG)** — PostgreSQL running inside EKS cluster
- **Cloudflare Tunnel** — zero-trust access to Jenkins and App (no public LoadBalancer needed)
- **AWS SSM Parameter Store** — secrets storage (Cloudflare token, GitHub token)
- **IRSA (IAM Roles for Service Accounts)** — Jenkins pod assumes IAM role without static credentials
- **EBS CSI Driver** — persistent storage for Jenkins on EKS
- **CloudWatch** — AWS-native monitoring, logging, alerting

---

## Architecture

```
git push (dev-penina-cloud branch)
  │
  ▼
AWS CodeBuild (coinops-terraform-apply)
  │  buildspec.yml: terraform init → terraform apply
  ▼
Terraform apply:
  ├── aws_network    — VPC, subnets, NAT, route tables
  ├── aws_security   — security groups
  ├── aws_vm         — EC2 instances (jump-host)
  ├── aws_lb         — ALB
  ├── aws_rds        — PostgreSQL (managed)
  ├── aws_eks        — EKS cluster + node group
  ├── aws_irsa       — OIDC provider + IAM roles for pods + EBS CSI Driver
  ├── aws_codebuild  — CodeBuild project itself (self-managing)
  ├── aws_monitoring — CloudWatch alarms, dashboards, log groups
  ├── helm_release.jenkins — Jenkins via Helm + JCasC
  └── cloudflare_*   — Cloudflare Tunnel for Jenkins
  │
  ▼
EKS Cluster (coinops-eks, eu-central-1):
  Namespace jenkins:
    jenkins-0         — Jenkins controller (StatefulSet, EBS persistent volume)
    cloudflared       — Cloudflare Tunnel agent for Jenkins
  │
  ▼
Jenkins (https://jenkins.coinops-softserve-penina.pp.ua)
  Job: coinops-eks-deploy-coinops (created via JCasC)
  │  Jenkinsfile: ci/jenkins/Jenkinsfile.eks-coinops
  ▼
Ansible playbook: ansible/eks-coinops.yml
  ├── Install CNPG operator (Helm)
  ├── Create PostgreSQL cluster (CNPG)
  ├── Role k3s_coinops:
  │     ├── namespaces (coinops-queue, coinops-app, coinops-frontend)
  │     ├── secrets (GHCR pull, DB, RabbitMQ)
  │     ├── queue layer (RabbitMQ + Redis)
  │     ├── app layer (schema-init, history-api, history-consumer, proxy)
  │     └── frontend (UI + Ingress)
  │
  ▼
EKS Cluster — CoinOps namespaces:
  coinops-queue:    RabbitMQ, Redis
  coinops-app:      PostgreSQL (CNPG), history-api, history-consumer, proxy
  coinops-frontend: UI (nginx + React), cloudflared
  │
  ▼
Cloudflare Tunnel → coinops-softserve-penina.pp.ua → UI pod

Monitoring:
  EKS → CloudWatch Logs → Metric Filters → Alarms → SNS → Email
```

---

## Application URLs

| Service | URL | Access |
|---------|-----|--------|
| CoinOps App | https://coinops-softserve-penina.pp.ua | Public ✅ |
| Jenkins | https://jenkins.coinops-softserve-penina.pp.ua | Public ✅ |
| CloudWatch Dashboard | AWS Console → CloudWatch → Dashboards → coinops-monitoring | AWS Console |

---

## AWS Infrastructure

| Resource | Details |
|----------|---------|
| EKS Cluster | `coinops-eks`, eu-central-1, v1.31, 2 worker nodes |
| CodeBuild Project | `coinops-terraform-apply` |
| IAM Roles | `coinops-eks-cluster-role`, `coinops-eks-node-role`, `coinops-codebuild-role`, `coinops-jenkins-irsa-role`, `coinops-eks-ebs-csi-role` |
| OIDC Provider | `oidc.eks.eu-central-1.amazonaws.com/id/6EE23C569128ED938AF68F106F8162F0` |
| SSM Parameters | `/coinops/cloudflare/api-token`, `/coinops/github/token`, `/coinops/rabbitmq/password` |
| Cloudflare Tunnels | `coinops-jenkins` (Healthy), `coinops-app` (Healthy) |

---

## Kubernetes Namespaces

| Namespace | Services | Purpose |
|-----------|---------|---------|
| `jenkins` | jenkins-0, cloudflared | CI/CD controller + tunnel |
| `cnpg-system` | CNPG operator | CloudNativePG operator |
| `coinops-queue` | RabbitMQ, Redis | Message queue + cache |
| `coinops-app` | proxy, history-api, history-consumer, coinops-db (CNPG) | Backend services + DB |
| `coinops-frontend` | ui, cloudflared | React UI + tunnel |

---

## Terraform Modules

```
terraform/
  main.tf                    — root module
  eks_jenkins.tf             — Jenkins Helm release + JCasC + Cloudflare resources
  provider.tf                — AWS, Helm, Kubernetes, Cloudflare, Random providers
  variables.tf               — input variables
  outputs.tf                 — jenkins_admin_password, jenkins_tunnel_token, alb_dns_name
  config.yaml                — infrastructure config (repo root)
  modules/
    aws_network/             — VPC, subnets, NAT gateway, route tables
    aws_security/            — security groups
    aws_vm/                  — EC2 instances (jump-host)
    aws_lb/                  — ALB + target group + listeners
    aws_rds/                 — RDS PostgreSQL (managed)
    aws_eks/                 — EKS cluster + node group + IAM roles
    aws_irsa/                — OIDC provider + IRSA roles + EBS CSI Driver addon
    aws_codebuild/           — CodeBuild project + IAM role
    aws_monitoring/
      alerting/              — SNS Topic + email subscription
      logs/                  — S3 bucket for ALB logs
      iam/                   — CloudWatch Agent IAM role
      ec2_alarms/            — CPU alarms
      alb_alarms/            — 5XX + HealthyHostCount alarms
      log_metrics/           — Log Groups + Metric Filters
      dashboard/             — CloudWatch Dashboard
      agent/                 — SSM Parameter with agent config
```

---

## Jenkins Configuration (JCasC)

Jenkins is fully configured as code — no manual clicking required:

**Files:**
- `helm/jenkins/values.yaml.tftpl` — Helm values template
- `helm/jenkins/casc.yaml.tftpl` — JCasC configuration template

**Auto-configured:**
- Admin user + password (from `random_password` Terraform resource)
- Kubernetes cloud (`eks`) for dynamic agents
- Credentials: `github-token`, `coinops-db-password`, `coinops-rabbitmq-password`
- Pipeline job `coinops-eks-deploy-coinops` pointing to `ci/jenkins/Jenkinsfile.eks-coinops`

---

## Jenkins Pipeline (Jenkinsfile)

File: `ci/jenkins/Jenkinsfile.eks-coinops`

**Stages:**
1. **Tools** — installs kubectl, helm, ansible, python deps
2. **Kubeconfig** — builds in-cluster kubeconfig from ServiceAccount token
3. **Deploy CoinOps** — runs `ansible-playbook ansible/eks-coinops.yml`

**Credentials used:**
- `coinops-db-password` → `DB_PASSWORD`
- `coinops-rabbitmq-password` → `RABBITMQ_PASSWORD`
- `github-token` → `GHCR_USERNAME` + `GHCR_TOKEN`

---

## Ansible Roles

| Role | Purpose |
|------|---------|
| `k3s_cnpg` | Installs CNPG operator via Helm |
| `k3s_coinops` | Deploys full CoinOps stack to EKS |

**Playbook:** `ansible/eks-coinops.yml`

---

## Secrets Management

| Secret | Storage | How used |
|--------|---------|---------|
| Jenkins admin password | Terraform `random_password` → Helm values | JCasC auto-configures |
| Cloudflare API token | AWS SSM `/coinops/cloudflare/api-token` | CodeBuild env var |
| GitHub token | AWS SSM `/coinops/github/token` + Jenkins credential | Clone repo + GHCR pull |
| DB password | CodeBuild env var → Terraform var → Jenkins credential | Ansible + app secrets |
| RabbitMQ password | AWS SSM `/coinops/rabbitmq/password` + Jenkins credential | App secrets |

**Never committed to git** ✅

---

## AWS Monitoring (CloudWatch)

| Resource | Name | Purpose |
|----------|------|---------|
| SNS Topic | `coinops-alerts` | Alert delivery |
| IAM Role | `coinops-cloudwatch-agent-role` | EC2 CloudWatch access |
| Log Group | `/coinops/proxy` | Proxy logs |
| Log Group | `/coinops/history` | History logs |
| Dashboard | `coinops-monitoring` | 5 widgets |
| Alarms | 5 total | CPU, 5XX, HealthyHosts, ProxyErrors |

---

## What Needs Automation (Technical Debt)

| Item | Current State | Fix Needed |
|------|--------------|-----------|
| cloudflared for Jenkins | Manual `kubectl apply` | Add as `kubernetes_deployment` in `eks_jenkins.tf` |
| cloudflared for App | Manual `kubectl apply` | Add as `kubernetes_deployment` in Terraform |
| Cloudflare Tunnel for App | Created manually in dashboard | Add `cloudflare_zero_trust_tunnel_cloudflared` in Terraform |
| RabbitMQ password | Created manually in Jenkins + SSM | Add `random_password` + SSM param in Terraform, pass via JCasC |
| Jenkins DNS CNAME | Fixed manually in Cloudflare | Fix `cloudflare_record.jenkins` content in `eks_jenkins.tf` |

---

## How to Deploy from Scratch

### 0. Bootstrap (one time only)
```bash
# In AWS CloudShell
bash bootstrap/aws/bootstrap.sh
```

### 1. Set SSM Parameters (one time only)
```bash
aws ssm put-parameter --name /coinops/cloudflare/api-token --value "TOKEN" --type SecureString --region eu-central-1
aws ssm put-parameter --name /coinops/github/token --value "TOKEN" --type SecureString --region eu-central-1
aws ssm put-parameter --name /coinops/rabbitmq/password --value "PASSWORD" --type SecureString --region eu-central-1
```

### 2. Trigger CodeBuild
```bash
aws codebuild start-build --project-name coinops-terraform-apply --region eu-central-1
# OR: git push origin dev-penina-cloud (if webhook configured)
```

### 3. Run Jenkins Pipeline
- Open https://jenkins.coinops-softserve-penina.pp.ua
- Login: admin / (from `terraform output -raw jenkins_admin_password`)
- Click `coinops-eks-deploy-coinops` → Build Now

### 4. Access App
- https://coinops-softserve-penina.pp.ua

---

## Problems & Solutions

**Problem 1 — Jenkins version mismatch**
Plugins required Jenkins 2.504.3 but image was 2.492.
Fix: bumped `tag` in `helm/jenkins/values.yaml.tftpl` to `2.504.3-jdk21`.

**Problem 2 — Helm timeout (context deadline exceeded)**
Jenkins pod stuck in `Init:CrashLoopBackOff` during Helm install.
Fix: updated Jenkins image version to match plugin requirements.

**Problem 3 — `ansible_env` undefined**
`eks-coinops.yml` used `ansible_env.HOME` with `gather_facts: false`.
Fix: replaced with hardcoded `/root/.kube/config` default.

**Problem 4 — CNPG not installed**
`schema-init` Job waited for `coinops-db-rw` that didn't exist.
Fix: added CNPG operator install + PostgreSQL cluster creation in `eks-coinops.yml`.

**Problem 5 — helm binary missing in Jenkins agent**
`kubernetes.core.helm` requires `helm` CLI on the agent.
Fix: added `curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash` to Jenkinsfile Tools stage.

**Problem 6 — RabbitMQ auth failure**
RabbitMQ started before secret with password was created; `RABBITMQ_PASSWORD` not in Ansible env.
Fix: added `coinops-rabbitmq-password` Jenkins credential; `kubectl rollout restart` after secret update.

**Problem 7 — GHCR 403 Forbidden**
GitHub token expired.
Fix: regenerated `ghcr-pull-coinops` token, updated Jenkins credential + SSM parameter.

**Problem 8 — Cloudflare DNS 1016 error**
Jenkins CNAME pointed to wrong address.
Fix: updated Target to `<tunnel-id>.cfargotunnel.com` in Cloudflare DNS.
