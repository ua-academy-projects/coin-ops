# CoinOps AWS Cloud Deployment — Report

**Branch:** `dev-penina-cloud`
**Domain:** https://coinops-penina.pp.ua
**Cloud:** AWS (eu-central-1)
**Last updated:** 12.05.2026

---

## Current State

- Application is **live** at https://coinops-penina.pp.ua
- Runtime mode: **external** (RabbitMQ + Redis in containers, PostgreSQL on AWS RDS)
- SSL: **Let's Encrypt** certificate via Certbot DNS challenge (valid until 2026-08-10, auto-renews)
- All 4 VMs running, all containers healthy

---

## What Changed Since Initial Deploy (12.05.2026)

### Config restructure — `terraform/config.yaml`

Mentor feedback: the `sizes` dictionary used nested `gcp/aws` keys but `regions` was flat. Restructured to be consistent:

**Before:**
```yaml
general:
  regions:
    aws:
      region: "eu-central-1"
      zone: "eu-central-1b"
```

**After:**
```yaml
general:
  location: "europe"

locations:
  europe:
    aws:
      region: "eu-central-1"
      zones:
        primary: "eu-central-1a"
        secondary: "eu-central-1b"
  us:
    aws:
      region: "us-east-1"
      zones:
        primary: "us-east-1a"
        secondary: "us-east-1b"
```

This allows per-VM zone assignment and multi-region support. Each VM now has `zone: primary` or `zone: secondary` in config.

### Side effect: VMs recreated

Changing availability zones caused Terraform to recreate all subnets and VMs (subnets are AZ-bound in AWS). New VMs came up clean — Ansible provision + deploy was re-run.

### AWS Load Balancer (aws_lb module)

Added `modules/aws_lb` with ALB, target group, and HTTP listener pointing to node-03. DNS in Cloudflare currently set to A record → node-03 public IP (ALB health check not yet configured for HTTPS).

---

## Infrastructure (Terraform)

| Resource | Details |
|----------|---------|
| **VPC** | `10.0.0.0/16` with DNS support |
| **Subnets** | public-a (`10.0.1.0/24`), public-b (`10.0.5.0/24`), private-a (`10.0.2.0/24`), private-b (`10.0.4.0/24`) |
| **NAT Gateway** | Allows private VMs to access internet (image pulls, apt updates) |
| **Internet Gateway** | Public subnet internet access |
| **EC2 — jump-host** | `t3.micro`, public subnet eu-central-1a, SSH gateway port 9922 |
| **EC2 — node-01** | `t3.micro`, private subnet eu-central-1a, history + queue |
| **EC2 — node-02** | `t3.micro`, private subnet eu-central-1a, proxy + cache |
| **EC2 — node-03** | `t3.micro`, public subnet eu-central-1b, frontend HTTPS |
| **RDS PostgreSQL** | `db.t3.micro`, PostgreSQL 16, `cognitor` database, private subnet |
| **ALB** | Application Load Balancer (created, DNS not yet pointing to it) |
| **Security Groups** | jump-host-sg, internal-sg, web-sg, rds-sg |

---

## Application Architecture

```
Browser → https://coinops-penina.pp.ua
         → Cloudflare DNS → node-03 public IP (18.197.0.66)
         → nginx (port 443, Let's Encrypt TLS)
           → /api/*         → Go proxy (node-02:8080) → CoinGecko/NBU/Polymarket APIs
                                                       → RabbitMQ (node-01:5672)
           → /history-api/* → FastAPI (node-01:8000)  → AWS RDS PostgreSQL
```

**Runtime mode: `external`**
- RabbitMQ on node-01 handles message queue
- Redis on node-02 handles session cache
- PostgreSQL on AWS RDS handles persistent storage (no DB container)

---

## Current IP Reference

| Resource | IP / Endpoint |
|----------|---------------|
| jump-host (public) | `3.68.198.185` |
| jump-host (internal) | `10.0.1.101` |
| node-01 (history+queue) | `10.0.2.96` |
| node-02 (proxy+cache) | `10.0.2.129` |
| node-03 (frontend) | `10.0.1.87` (public: `18.197.0.66`) |
| RDS PostgreSQL endpoint | `coinops-db.cj8kme8e0kqa.eu-central-1.rds.amazonaws.com:5432` |
| ALB DNS | `coinops-alb-635754233.eu-central-1.elb.amazonaws.com` |
| Domain | `coinops-penina.pp.ua` |

> Note: jump-host and node IPs change on VM recreation. Always run `terraform output` to get current IPs.

---

## How to Connect

```bash
# Start SSH agent and add key
eval $(ssh-agent -s)
ssh-add /c/Users/ASUS/.ssh/id_ed25519

# Connect to jump-host with agent forwarding
ssh -A -p 9922 marta_ops@3.68.198.185

# From jump-host, connect to internal nodes
ssh -p 9922 marta_ops@10.0.2.96    # node-01
ssh -p 9922 marta_ops@10.0.2.129   # node-02
ssh -p 9922 marta_ops@10.0.1.87    # node-03
```

---

## How to Redeploy

From jump-host (ansible files are in `~/ansible/`):

```bash
# Set environment variables
export RABBITMQ_PASSWORD=changeme_rabbit
export DB_PASSWORD=<rds password>
export RUNTIME_BACKEND=external
export GHCR_USERNAME=MartaPenina
export GHCR_TOKEN=<github token>
export SSH_KEY_PATH=~/.ssh/id_ed25519

# Provision (installs Docker, configures firewall)
ansible-playbook -i ~/ansible/inventory ~/ansible/provision.yml

# Deploy containers
IMAGE_TAG=dev-latest ansible-playbook -i ~/ansible/inventory ~/ansible/deploy.yml
```

---

## SSL Certificate

Certificate obtained via Certbot DNS challenge through Cloudflare API:

```bash
# Certificate location on node-03
/etc/letsencrypt/live/coinops-penina.pp.ua/fullchain.pem
/etc/letsencrypt/live/coinops-penina.pp.ua/privkey.pem

# Copied to nginx volume
/etc/cognitor/tls/coinops.crt
/etc/cognitor/tls/coinops.key
```

Auto-renewal configured via Certbot systemd timer. Expires 2026-08-10.

After renewal, copy certs and restart nginx:
```bash
sudo cp /etc/letsencrypt/live/coinops-penina.pp.ua/fullchain.pem /etc/cognitor/tls/coinops.crt
sudo cp /etc/letsencrypt/live/coinops-penina.pp.ua/privkey.pem /etc/cognitor/tls/coinops.key
cd /opt/cognitor/ui && sudo docker compose down && sudo docker compose up -d
```

---

## What's Next

- **ALB with HTTPS** — configure ALB health check on port 443, point Cloudflare CNAME to ALB DNS instead of direct node-03 IP
- **ElastiCache** — replace Redis container on node-02 with AWS managed ElastiCache
- **SQS** — replace RabbitMQ container on node-01 with AWS managed Simple Queue Service
- **CI/CD** — GitHub Actions triggers Ansible deploy automatically on merge to dev

---

## Cost Management

NAT Gateway + RDS + ALB cost ~$3-4/day. When done:

```bash
cd /d/DevOps_internship/coin-ops/terraform
terraform destroy
```
