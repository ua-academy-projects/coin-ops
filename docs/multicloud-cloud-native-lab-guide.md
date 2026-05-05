# Multicloud Cloud-Native Terraform Lab Guide

This document explains the multicloud Terraform and Ansible work in this repository as if you are reading it as a junior DevOps engineer. The goal is not only to know which commands to run, but to understand why the code is shaped this way and how it behaves when you switch between AWS and GCP.

## 1. Goal Of The Work

The task was to move from a cloud-specific VM lab into a more realistic cloud-native deployment layer.

The requirements were:

- One Terraform root configuration.
- One neutral YAML input file.
- Switch target cloud by changing a value such as `cloud: aws` or `cloud: gcp`.
- Create infrastructure with Terraform.
- Deploy the application to app VMs with Ansible.
- Do not run the application on the bastion.
- Put the UI behind a load balancer.
- Later, use a real domain and HTTPS.

The target architecture for AWS is:

```text
Browser
  -> HTTP/HTTPS Load Balancer
  -> private app VM 1 / private app VM 2
  -> private DB/runtime VM

Operator SSH
  -> bastion VM
  -> private app/db VMs through ProxyJump
```

The current full cloud-native implementation is AWS. GCP is still wired into the same root through a compatibility module, but the complete GCP load-balancer/application architecture is not built yet.

## 2. Main Files

The active lab lives here:

```text
terraform/multicloud-vm-yaml-lab
```

Important Terraform files:

```text
terraform/multicloud-vm-yaml-lab/config/lab.yaml
terraform/multicloud-vm-yaml-lab/main.tf
terraform/multicloud-vm-yaml-lab/locals.config.tf
terraform/multicloud-vm-yaml-lab/providers.tf
terraform/multicloud-vm-yaml-lab/backend.tf
terraform/multicloud-vm-yaml-lab/backend.hcl
terraform/multicloud-vm-yaml-lab/versions.tf
terraform/multicloud-vm-yaml-lab/checks.tf
terraform/multicloud-vm-yaml-lab/outputs.tf
terraform/multicloud-vm-yaml-lab/modules/aws-cloud-native
terraform/multicloud-vm-yaml-lab/modules/gcp-stack
```

Important Ansible files:

```text
ansible/cloud-provision.yml
ansible/cloud-deploy.yml
ansible/group_vars/all/main.yml
ansible/group_vars/app/main.yml
ansible/group_vars/db/main.yml
ansible/group_vars/bastion/main.yml
ansible/templates/cloud-app.compose.yaml.j2
ansible/templates/cloud-db.compose.yaml.j2
ansible/templates/cloud-nginx.conf.j2
```

Old folders still exist as references:

```text
terraform/multicloud-vm-yaml-lab/roots/aws
terraform/multicloud-vm-yaml-lab/roots/gcp
```

Those old root folders are not the new target structure. The new target is the root directly inside `terraform/multicloud-vm-yaml-lab`.

## 3. The One-Root Idea

Before this work, AWS and GCP had separate root folders. That is easy at first, but it creates duplication:

```text
roots/aws/main.tf
roots/gcp/main.tf
```

The new approach keeps one root:

```hcl
module "aws" {
  count  = local.is_aws ? 1 : 0
  source = "./modules/aws-cloud-native"

  config = local.config
}

module "gcp" {
  count  = local.is_gcp ? 1 : 0
  source = "./modules/gcp-stack"

  config = local.config
}
```

This means:

- Terraform always reads the same root files.
- The YAML decides which cloud is active.
- If `cloud: aws`, the AWS module count is `1` and the GCP module count is `0`.
- If `cloud: gcp`, the GCP module count is `1` and the AWS module count is `0`.

This is why the root module stays small. It does not create AWS resources directly. It delegates the selected cloud to a child module.

## 4. The Neutral YAML File

The main input file is:

```text
terraform/multicloud-vm-yaml-lab/config/lab.yaml
```

At the top you choose the cloud:

```yaml
cloud: aws
location: eu_central
```

This is intentionally neutral. It does not say `aws_region: eu-central-1` at the top level. Instead, it says:

```yaml
location: eu_central
```

Then the catalog translates that logical location into cloud-specific values:

```yaml
catalog:
  locations:
    eu_central:
      gcp:
        region: europe-central2
        zone: europe-central2-a
      aws:
        region: eu-central-1
        availability_zones:
          - eu-central-1a
          - eu-central-1b
```

So the YAML has two layers:

1. Human/lab intent: `location: eu_central`, `size: micro`, `image: ubuntu_2204`.
2. Cloud translation catalog: AWS and GCP values for that intent.

This is the dictionary idea you asked about.

Example:

```yaml
defaults:
  size: micro
  image: ubuntu_2204
  disk_size_gb: 10
  network: lab
```

And later:

```yaml
catalog:
  sizes:
    micro:
      gcp: e2-micro
      aws: t3.micro
  images:
    ubuntu_2204:
      gcp: ubuntu-os-cloud/ubuntu-2204-lts
      aws:
        owners:
          - '099720109477'
        name_filter: ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*
```

That means the VM config can say only `micro`, and the AWS module turns that into `t3.micro` while the GCP module turns it into `e2-micro`.

## 5. How Terraform Reads YAML

The root reads YAML in `locals.config.tf`:

```hcl
locals {
  raw_config = yamldecode(file("${path.module}/config/lab.yaml"))
}
```

Then it normalizes defaults and cloud-specific values into `local.config`.

Important idea:

- `local.config` belongs to the root module.
- The child module does not automatically see root locals.
- The root passes `local.config` into the child module as an input variable.

Root:

```hcl
module "aws" {
  source = "./modules/aws-cloud-native"
  config = local.config
}
```

Child module:

```hcl
variable "config" {
  type = any
}
```

Inside the child module, it is accessed as:

```hcl
local.config = var.config
```

This is the answer to the earlier confusion about `local.config` vs `var.*`:

- Root reads and prepares config as `local.config`.
- Root passes it to child as `config = local.config`.
- Child receives it as `var.config`.
- Child may create its own local helper called `local.config = var.config`.

There is no magical shared local. Each module has its own scope.

## 6. Terraform Backend And State

The backend is declared separately now:

```text
backend.tf
backend.hcl
```

`backend.tf` only says that this root uses an S3 backend:

```hcl
terraform {
  backend "s3" {}
}
```

`backend.hcl` contains the actual backend settings:

```hcl
bucket      = "coinops-leev1tan-terraform-state-001"
key         = "multicloud-vm-yaml-lab/terraform.tfstate"
region      = "eu-central-1"
profile     = "coinops-lab"
use_lockfile = true
```

The reason for splitting these:

- `backend.tf` is structural Terraform code.
- `backend.hcl` is environment-specific backend configuration.
- This lets you run:

```bash
terraform init -backend-config=backend.hcl -reconfigure
```

For multiple clouds, use Terraform workspaces:

```bash
terraform workspace select aws || terraform workspace new aws
```

This keeps AWS and GCP state separated even though they share one root.

Important: Terraform state is stored in the S3 bucket after real backend init. The local files reference the backend, but the actual state lives remotely.

## 7. Provider Configuration

Provider versions are in:

```text
versions.tf
```

This file says which providers the root uses:

```hcl
required_providers {
  aws = {
    source  = "hashicorp/aws"
    version = "~> 6.0"
  }
  google = {
    source  = "hashicorp/google"
    version = "~> 6.0"
  }
  cloudflare = {
    source  = "cloudflare/cloudflare"
    version = "~> 5.0"
  }
}
```

Provider runtime configuration is in:

```text
providers.tf
```

The AWS provider gets region/profile from YAML:

```hcl
provider "aws" {
  region  = local.aws_region
  profile = try(local.config.clouds.aws.profile, null)
}
```

Cloudflare uses `CLOUDFLARE_API_TOKEN` from your environment. That token is not stored in Git.

## 8. Validation Checks

`checks.tf` contains guardrails.

Examples of checks:

- Is `cloud` one of the supported values?
- Does the workspace match the selected cloud?
- Does the SSH public key exist?
- Are SSH source ranges configured?
- If domain is enabled, is Cloudflare Zone ID set?

These checks exist to fail early with a human-readable message instead of letting AWS/GCP fail later in a more confusing way.

## 9. AWS Module Architecture

The full AWS implementation is inside:

```text
terraform/multicloud-vm-yaml-lab/modules/aws-cloud-native
```

It creates this architecture:

```text
VPC 10.10.0.0/16

Public subnet A 10.10.0.0/24
  - bastion VM
  - NAT Gateway
  - ALB node

Public subnet B 10.10.1.0/24
  - ALB node

Private subnet A 10.10.10.0/24
  - app-1
  - db

Private subnet B 10.10.11.0/24
  - app-2
```

Why public and private subnets?

- Public subnets have a route to the Internet Gateway.
- Private subnets do not expose VMs directly to the internet.
- Private VMs use the NAT Gateway only for outbound internet access, such as apt updates and Docker pulls.

This is more cloud-native than giving every VM a public IP.

## 10. AWS Network Resources

The module creates:

```hcl
aws_vpc.this
aws_internet_gateway.this
aws_subnet.public
aws_subnet.private
aws_route_table.public
aws_route.public_internet
aws_route_table.private
aws_route.private_nat
aws_nat_gateway.this
aws_eip.nat
```

The route behavior is:

```text
Public subnets:
0.0.0.0/0 -> Internet Gateway

Private subnets:
0.0.0.0/0 -> NAT Gateway
```

This means:

- The bastion and load balancer can be public.
- App and DB VMs stay private.
- App and DB VMs can still download packages/images.

Cost warning: NAT Gateway is useful and realistic, but it costs money. For a pure cheap lab, you might replace it with public app VMs temporarily or a NAT instance, but that is less clean.

## 11. Security Groups

The AWS module creates separate security groups:

```text
bastion SG
load balancer SG
app SG
db SG
```

Bastion SG:

```text
allow SSH 22 only from firewall.ssh_source_ranges
```

Load balancer SG:

```text
allow HTTP 80 from web_source_ranges
allow HTTPS 443 from web_source_ranges
```

App SG:

```text
allow HTTP 80 only from load balancer SG
allow SSH 22 only from bastion SG
```

DB SG:

```text
allow SSH 22 only from bastion SG
allow PostgreSQL 5432 only from app SG
allow RabbitMQ 5672 only from app SG
allow Redis 6379 only from app SG
optional ICMP from bastion SG
```

This is important. We are not saying `allow 5432 from 0.0.0.0/0`. The DB is private and only the app VMs can talk to it.

## 12. Bastion Behavior

The bastion exists only for admin access.

It has:

```text
public IP: yes
app running: no
purpose: SSH jump host
```

The app and DB VMs have:

```text
public IP: no
SSH access: through bastion only
```

Terraform outputs SSH config so you do not manually rewrite hostnames every time AWS gives a new public IP:

```bash
terraform output -raw ssh_config > ~/.ssh/aws-multicloud-lab.generated
```

Then include it from `~/.ssh/config`:

```sshconfig
Include ~/.ssh/aws-multicloud-lab.generated
```

After each apply, regenerate the file. This solves the changing public IP problem.

## 13. Load Balancer Behavior

The load balancer is created with:

```hcl
resource "aws_lb" "app" {
  name               = "${local.name_prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.lb.id]
  subnets            = [for subnet in aws_subnet.public : subnet.id]
}
```

Meaning:

- It is public because `internal = false`.
- It is an Application Load Balancer.
- It lives in the public subnets.
- It receives traffic from the browser.

The target group is:

```hcl
resource "aws_lb_target_group" "app" {
  port     = local.app_port
  protocol = "HTTP"
  vpc_id   = aws_vpc.this.id
}
```

The app VMs are attached to it:

```hcl
resource "aws_lb_target_group_attachment" "app" {
  for_each = aws_instance.app

  target_group_arn = aws_lb_target_group.app.arn
  target_id        = each.value.id
  port             = local.app_port
}
```

So traffic flow is:

```text
browser -> ALB -> target group -> app-1/app-2 on port 80
```

When `domain.enabled: false`, Terraform creates an HTTP listener:

```text
ALB port 80 -> app target group port 80
```

When `domain.enabled: true`, Terraform creates:

```text
ALB port 443 -> app target group port 80
ALB port 80 -> redirect to 443
```

The app containers do not need to know about HTTPS. HTTPS terminates at the load balancer.

## 14. Domain And HTTPS Behavior

Domain config is in YAML:

```yaml
domain:
  enabled: false
  name: coinops.example.pp.ua
  cloudflare_zone_id: REPLACE_WITH_CLOUDFLARE_ZONE_ID
  create_records: true
```

For now it is disabled because you do not have the domain yet.

When enabled, Terraform creates:

```text
AWS ACM certificate
Cloudflare DNS validation record
AWS ACM certificate validation
ALB HTTPS listener on 443
ALB HTTP redirect from 80 to 443
Cloudflare CNAME record pointing your domain to the ALB DNS name
```

You will need:

```bash
export CLOUDFLARE_API_TOKEN="your-token"
```

Cloudflare token permissions should be minimal:

```text
Zone:Read
DNS:Edit
```

Only for the zone you are using.

After apply, the output becomes:

```text
https://your-domain
```

Until then, output is the raw ALB URL:

```text
http://something.eu-central-1.elb.amazonaws.com
```

## 15. Terraform Outputs

The root exposes useful outputs:

```text
app_url
bastion_public_ip
instances
ssh_config
ansible_inventory
load_balancer
```

Important commands:

```bash
terraform output app_url
terraform output load_balancer
terraform output -raw ssh_config
terraform output -raw ansible_inventory
```

`app_url` is what you open in a browser.

`load_balancer` shows the ALB DNS name and whether HTTPS is enabled.

`ssh_config` generates SSH aliases.

`ansible_inventory` generates the dynamic inventory for deployment.

## 16. Ansible Provisioning

Terraform creates infrastructure. Ansible configures the VMs and deploys the application.

Provisioning playbook:

```text
ansible/cloud-provision.yml
```

It does:

- Validate required environment variables.
- Run common system setup.
- Install Docker.
- Create DB/runtime directories on the DB VM.

It targets the generated inventory groups:

```text
cloud
app
db
bastion
```

The inventory comes from Terraform:

```bash
terraform output -raw ansible_inventory > ../../ansible/inventory.cloud
```

## 17. Ansible Deployment

Deployment playbook:

```text
ansible/cloud-deploy.yml
```

It does three main things.

First, it validates local environment variables:

```text
DB_PASSWORD
SSH_KEY_PATH
RUNTIME_BACKEND
```

Second, it deploys DB/runtime services to the private DB VM:

```text
PostgreSQL
RabbitMQ
Redis
```

Third, it deploys app services to both app VMs:

```text
history-api
history-consumer
proxy
ui/nginx
```

The app VMs expose port 80 locally. The AWS ALB sends traffic to that port.

## 18. Host Firewall With UFW

The existing Ansible `common` role enables UFW. That means AWS Security Groups alone are not enough.

So new group vars were added:

```text
ansible/group_vars/app/main.yml
ansible/group_vars/db/main.yml
ansible/group_vars/bastion/main.yml
```

App allows:

```yaml
common_allowed_ports: [22, 80]
```

DB allows:

```yaml
common_allowed_ports: [22, 5432, 5672, 6379]
```

Bastion allows:

```yaml
common_allowed_ports: [22]
```

This lines up host firewall rules with AWS security groups.

## 19. How To Apply AWS

From WSL:

```bash
cd ~/projects/softserv-internship/terraform/multicloud-vm-yaml-lab
```

Initialize backend:

```bash
terraform init -backend-config=backend.hcl -reconfigure
```

Use AWS workspace:

```bash
terraform workspace select aws || terraform workspace new aws
```

Check plan:

```bash
terraform plan
```

Apply:

```bash
terraform apply
```

Generate helper files:

```bash
terraform output -raw ssh_config > ~/.ssh/aws-multicloud-lab.generated
terraform output -raw ansible_inventory > ../../ansible/inventory.cloud
```

Make sure SSH config includes the generated file:

```sshconfig
Include ~/.ssh/aws-multicloud-lab.generated
```

If it is not there, add it once.

## 20. How To Deploy The App

From repo root:

```bash
cd ~/projects/softserv-internship
```

Export required variables:

```bash
export SSH_KEY_PATH=~/.ssh/coinops_gcp_jump
export DB_PASSWORD='your-db-password'
export RABBITMQ_PASSWORD='your-rabbit-password'
export RUNTIME_BACKEND=external
```

If images are private in GHCR, also export:

```bash
export GHCR_USERNAME='your-github-user'
export GHCR_TOKEN='your-github-token'
```

Provision VMs:

```bash
ansible-playbook -i ansible/inventory.cloud ansible/cloud-provision.yml
```

Deploy app:

```bash
ansible-playbook -i ansible/inventory.cloud ansible/cloud-deploy.yml
```

Open app:

```bash
cd terraform/multicloud-vm-yaml-lab
terraform output app_url
```

## 21. What You Should See In AWS

In AWS Console:

```text
VPC -> Your VPCs -> coinops-lab-vpc
VPC -> Subnets -> coinops-lab-public-0/1, coinops-lab-private-0/1
EC2 -> Instances -> coinops-lab-bastion, coinops-lab-app-1, coinops-lab-app-2, coinops-lab-db
EC2 -> Load Balancers -> coinops-lab-alb
EC2 -> Target Groups -> coinops-lab-app-tg
EC2 -> Security Groups -> coinops-lab-* SGs
```

Before Ansible deploy, the load balancer target group may show app targets as unhealthy.

After Ansible deploy, the target group should show:

```text
coinops-lab-app-1 healthy
coinops-lab-app-2 healthy
```

The health check path is:

```text
/health
```

## 22. How Switching Cloud Works

To switch cloud, edit YAML:

```yaml
cloud: gcp
```

or:

```yaml
cloud: aws
```

Then use the matching workspace:

```bash
terraform workspace select gcp || terraform workspace new gcp
```

or:

```bash
terraform workspace select aws || terraform workspace new aws
```

The check in `checks.tf` expects workspace and cloud to match. This prevents accidentally applying AWS config into a GCP-named state or the reverse.

Important current limitation:

- AWS has the full new cloud-native implementation.
- GCP is wired through `modules/gcp-stack`, but it is not yet equivalent to the AWS ALB/app/db architecture.

## 23. Why Not Use As Many Tiny Modules As Possible

More modules are not automatically better.

A good module should hide a meaningful boundary:

- network
- firewall/security
- compute
- load balancer
- DNS/certificate
- full cloud stack

For this lab, the AWS implementation is currently in one `aws-cloud-native` module. That is intentional because the resources are tightly connected:

- ALB needs public subnets and SGs.
- App VMs need private subnets and SGs.
- Target group attachments need app instances.
- Certificate and DNS need the load balancer.

Splitting too early can make the lab harder to understand because outputs and inputs multiply everywhere.

A senior path would be:

1. First make the full AWS stack work in one module.
2. Once behavior is stable, split into internal modules if needed:

```text
aws-network
aws-security
aws-compute
aws-load-balancer
aws-dns
```

But only split when it reduces complexity, not just because modules exist.

## 24. Secrets And Credentials

Do not put cloud credentials in YAML.

AWS credentials are loaded through the AWS profile:

```yaml
clouds:
  aws:
    profile: coinops-lab
```

That profile points to credentials in:

```text
~/.aws/credentials
~/.aws/config
```

Cloudflare token comes from environment variable:

```bash
export CLOUDFLARE_API_TOKEN="..."
```

Ansible secrets come from environment variables:

```bash
export DB_PASSWORD='...'
export RABBITMQ_PASSWORD='...'
export GHCR_TOKEN='...'
```

SSH key paths are in YAML, but the private key content is not:

```yaml
ssh:
  public_key_path: ~/.ssh/coinops_gcp_jump.pub
  private_key_path: ~/.ssh/coinops_gcp_jump
```

Terraform reads the public key and sends it to AWS. It does not upload your private key.

## 25. What Was Verified

The following checks passed after WSL was moved to the larger disk:

```text
terraform fmt -recursive
terraform init -backend=false -reconfigure
terraform validate
ansible-playbook --syntax-check ansible/cloud-provision.yml
ansible-playbook --syntax-check ansible/cloud-deploy.yml
temporary backend-free terraform plan
```

The temporary plan produced:

```text
Plan: 30 to add, 0 to change, 0 to destroy
```

That plan included:

```text
VPC
public/private subnets
internet gateway
NAT gateway
route tables
security groups
key pair
bastion VM
2 app VMs
DB VM
ALB
target group
target attachments
HTTP listener
outputs
```

## 26. Known Limitations And Next Steps

Current limitations:

- Domain/HTTPS is disabled until you acquire a domain and Cloudflare zone.
- GCP is not yet fully equivalent to AWS cloud-native stack.
- NAT Gateway costs money.
- App deploy assumes container images are available from the configured registry.
- The generated SSH config must be regenerated after Terraform recreates public IPs.

Next useful improvements:

1. Add a script to write SSH config and Ansible inventory automatically after apply.
2. Add a cheaper AWS lab mode without NAT Gateway.
3. Complete GCP equivalent: managed instance group, HTTPS load balancer, private DB VM or Cloud SQL.
4. Add Cloudflare/domain documentation once the real domain is acquired.
5. Add a README quickstart that links to this guide.

## 27. Mental Model Summary

Think of the project in layers:

```text
YAML
  describes desired lab intent in neutral words

Terraform root
  reads YAML, chooses cloud, passes config to one child module

Cloud module
  translates neutral config into AWS/GCP resources

Terraform outputs
  generate app URL, SSH config, and Ansible inventory

Ansible
  uses generated inventory to configure VMs and run containers

Load balancer
  exposes app VMs to browser without exposing app VMs publicly
```

That is the main thing to understand. YAML is the intent. Terraform is infrastructure. Ansible is software deployment. The load balancer is the public entrypoint. Bastion is only admin access.