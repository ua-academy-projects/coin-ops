# Deployment

This document describes the current deployment flow for `coin-ops` using:

- Terraform for infrastructure
- Ansible for provisioning and deployment
- Docker Compose for runtime services

The active multi-cloud flow lives under:

```text
terraform.gcp.aws/
```

The recommended entrypoint is:

```bash
./deploy.sh
```

## Overview

`deploy.sh` performs the full deployment pipeline:

1. loads deployment secrets from AWS Secrets Manager
2. resolves the target cloud
3. runs `terraform init`
4. runs `terraform apply`
5. generates `ansible/inventory.generated`
6. runs `ansible/provision.yml`
7. runs `ansible/deploy.yml`

## Prerequisites

- Python 3 and Ansible installed locally
- Terraform installed locally
- AWS CLI configured locally
- `jq` installed locally
- SSH private key available on the local machine

Initial setup:

```bash
export SSH_KEY_PATH=/home/valentyn/.ssh/coinops
export AWS_SECRETS_ID=coinops/app
export AWS_REGION=eu-central-1
ansible-galaxy collection install -r ansible/requirements.yml
```

## Cloud Selection

Cloud selection is controlled by Terraform variable `cloud` in:

[terraform.gcp.aws/variables.tf](/home/valentyn/Devops/git.repo/coin-ops/coin-ops/terraform.gcp.aws/variables.tf)

You can also override it at runtime:

```bash
CLOUD_PROVIDER=aws ./deploy.sh
CLOUD_PROVIDER=gcp ./deploy.sh
```

If `CLOUD_PROVIDER` is not set, `deploy.sh` uses the default from
`terraform.gcp.aws/variables.tf`.

## Deploy to GCP

GCP uses the historical local-database flow on the app VM. It does not use AWS
RDS.

If you deploy with local Docker images:

```bash
./scripts/build-local-images.sh
```

Then run:

```bash
CLOUD_PROVIDER=gcp ./deploy.sh
```

After deployment, get the load balancer IP:

```bash
terraform -chdir=terraform.gcp.aws output
```

Open:

```text
http://<load_balancer_ip_address>
```

Cloudflare for GCP:

- use an **A record**
- point it to the GCP load balancer IP

## Deploy to AWS

AWS supports:

- local Docker images
- registry images
- external PostgreSQL via AWS RDS

If you use the RDS flow, keep:

```text
RUNTIME_BACKEND=external
EXTERNAL_DB_HOST=<rds-endpoint>
```

Then run:

```bash
CLOUD_PROVIDER=aws ./deploy.sh
```

After deployment, get the load balancer output:

```bash
terraform -chdir=terraform.gcp.aws output
```

Open either:

```text
http://<load_balancer_dns_name>
```

or your public domain if Cloudflare is configured.

Cloudflare for AWS:

- use a **CNAME**
- point it to the ELB DNS name

## Local Images vs Registry Images

The deployment mode is controlled by `.env`:

```text
IMAGE_SOURCE=local
IMAGE_SOURCE=registry
```

### Local images

When `IMAGE_SOURCE=local`, Ansible expects tar archives in:

```text
.artifacts/images/
```

Build them with:

```bash
./scripts/build-local-images.sh
```

### Registry images

When `IMAGE_SOURCE=registry`, the deploy pulls images from GHCR.

If the images are private, set:

```bash
export GHCR_USERNAME=...
export GHCR_TOKEN=...
```

## Manual Flow

If you do not want to use `deploy.sh`, run the steps manually.

Provision infrastructure:

```bash
terraform -chdir=terraform.gcp.aws apply -var="cloud=<aws|gcp>"
```

Terraform writes inventory automatically to:

```text
ansible/inventory.generated
```

Install host dependencies:

```bash
ansible-playbook -i ansible/inventory.generated ansible/provision.yml
```

Deploy containers:

```bash
ansible-playbook -i ansible/inventory.generated ansible/deploy.yml
```

## Separate Database Inventory Mode

There is still a supported inventory mode with a separate `[db]` group.

See:

[ansible/inventory.aws.example](/home/valentyn/codex/coin-ops/ansible/inventory.aws.example)

This layout is useful for the older AWS-style flow where PostgreSQL runs on a
dedicated VM.

## Troubleshooting

### Load balancer is up but the page does not open

Check whether the application was actually deployed:

```bash
ansible -i ansible/inventory.generated coinops-web -b -m shell -a 'docker ps'
ansible -i ansible/inventory.generated coinops-app -b -m shell -a 'docker ps'
```

If there are no containers, infrastructure exists but deploy did not finish.

### `IMAGE_SOURCE=local` but nothing starts

Check that tar archives exist:

```bash
ls -la .artifacts/images
```

If this directory is empty, build the local images first:

```bash
./scripts/build-local-images.sh
```

### `load balancer output is unavailable`

This usually means `terraform output` is failing, often because of a syntax
error in `terraform.gcp.aws/variables.tf` or another Terraform file.

Check with:

```bash
terraform -chdir=terraform.gcp.aws output
```

## Historical Note

Older documentation and some older docs in the repository still describe the
original Hyper-V / static-IP VM flow. That material is useful for historical
context, but the current deployment path for this repository is:

```text
terraform.gcp.aws + ansible/inventory.generated + deploy.sh
```
