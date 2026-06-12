# CoinOps — Technical Debt & Improvements

## 1. ALB Health Check — Traefik /ping endpoint

**Current state:** `matcher = "200,404"` — ALB accepts 404 as healthy response.

**Why it's not ideal:** 404 means Traefik is alive but doesn't prove it's routing correctly. A proper health check should verify the proxy itself responds with 200.

**Correct solution:**
1. Add Traefik ping entrypoint on port 9000 via k3s HelmChart values:
```yaml
# In k3s Traefik HelmChart config
additionalArguments:
  - "--ping=true"
  - "--ping.entrypoint=ping"
entryPoints:
  ping:
    address: ":9000"
```

2. Open port 9000 in k3s security group (`modules/aws_security/main.tf`):
```hcl
ingress {
  from_port   = 9000
  to_port     = 9000
  protocol    = "tcp"
  cidr_blocks = ["10.0.0.0/16"]  # VPC only — ALB to nodes
  description = "Traefik ping health check"
}
```

3. Update ALB health check (`modules/aws_lb/main.tf`):
```hcl
health_check {
  protocol            = "HTTP"
  path                = "/ping"
  port                = "9000"
  healthy_threshold   = 2
  unhealthy_threshold = 2
  interval            = 10
  matcher             = "200"
}
```

---

## 2. k3s_cnpg Ansible Role — Single Responsibility

**Current state:** Role creates namespace, secret, and CNPG Cluster — but Helm chart also manages these resources. Conflict was resolved manually with kubectl labels.

**Correct solution:** `k3s_cnpg` role should only install the CNPG operator. Already fixed locally — push to repo:

```bash
git add ansible/roles/k3s_cnpg/tasks/main.yml
git commit -m "refactor: k3s_cnpg role installs operator only"
git push origin dev-penina-cloud
```

---

## 3. Terraform State — outputs.tf was corrupted

**What happened:** `modules/aws_vm/outputs.tf` was accidentally overwritten with `main.tf` content.

**Prevention:** Always check `git diff` before committing. Add pre-commit hook.

---

## 4. CloudWatch Agent — verify logs are flowing

**Current state:** Agent installed and started on all 3 nodes. SSM config fetched successfully.

**To verify:**
1. AWS Console → CloudWatch → Log Groups → `/coinops/proxy`
2. Check if Log Streams appear (one per instance ID)
3. If empty — check agent status on VM:
```bash
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -m ec2 -a status
```

---

## 5. SNS Email Subscription — confirm

**Current state:** Subscription email sent to marta.penina.academic@gmail.com but not confirmed.

**Action:** Click "Confirm subscription" in Gmail → after confirmation alarms will send emails.
