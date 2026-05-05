# Multicloud Lab Variables

This file is the memory sheet for variables used by the Terraform + Ansible cloud lab.

## Where To Put Values

Use a local `.env` file for secrets and shell variables:

```bash
cp terraform/multicloud-vm-yaml-lab/.env.cloud.example .env
source .env
```

Real `.env` files are ignored by Git. Do not commit real passwords or tokens.

## Required For Terraform

Most Terraform values come from:

```text
terraform/multicloud-vm-yaml-lab/config/lab.yaml
terraform/multicloud-vm-yaml-lab/backend.hcl
```

Backend/profile values:

| Variable | Where | Meaning |
| --- | --- | --- |
| `cloud` | `config/lab.yaml` | Selects `aws` or `gcp`. |
| `location` | `config/lab.yaml` | Logical location, translated through the catalog. |
| `clouds.aws.profile` | `config/lab.yaml` | AWS CLI profile used by AWS provider. |
| `profile` | `backend.hcl` | AWS CLI profile used by S3 backend. |
| `bucket` | `backend.hcl` | S3 bucket for Terraform state. |
| `key` | `backend.hcl` | State object path inside the bucket. |

Cloudflare:

| Variable | Required When | Meaning |
| --- | --- | --- |
| `CLOUDFLARE_API_TOKEN` | `domain.enabled=true` and `create_records=true` | Lets Terraform create DNS records in Cloudflare. |

Cloudflare token permissions:

```text
Zone:Read
DNS:Edit
```

## Required For Ansible Deploy

| Variable | Required | Default | Meaning |
| --- | --- | --- | --- |
| `SSH_KEY_PATH` | yes | none | Private SSH key used by Ansible. |
| `DB_PASSWORD` | yes | none | PostgreSQL password for app database. |
| `RABBITMQ_PASSWORD` | yes | none | RabbitMQ password. |
| `RUNTIME_BACKEND` | no | `external` | `external` uses RabbitMQ + Redis; `postgres` uses PostgreSQL runtime path. |
| `IMAGE_REGISTRY` | no | `ghcr.io/ua-academy-projects` | Container registry/org prefix. |
| `IMAGE_TAG` | no | `dev-latest` | Container image tag to deploy. |
| `GHCR_USERNAME` | if private packages | empty | GitHub username for GHCR login. |
| `GHCR_TOKEN` | if private packages | empty | GitHub token with package read access. |

## Common Commands

Run Terraform plan:

```bash
cd terraform/multicloud-vm-yaml-lab
./scripts/lab.sh plan
```

Apply infrastructure and regenerate SSH/Ansible files:

```bash
./scripts/lab.sh apply
```

Deploy app after exporting variables:

```bash
cd ~/projects/softserv-internship
source .env
cd terraform/multicloud-vm-yaml-lab
./scripts/lab.sh deploy
```

One-command apply + deploy:

```bash
source .env
cd terraform/multicloud-vm-yaml-lab
AUTO_APPROVE=true ./scripts/lab.sh full
```

## Generated Files

These are generated locally and should not be committed:

```text
~/.ssh/aws-multicloud-lab.generated
ansible/inventory.cloud
```

`./scripts/lab.sh apply` and `./scripts/lab.sh outputs` regenerate them.