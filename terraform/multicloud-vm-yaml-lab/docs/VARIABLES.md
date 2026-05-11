# Multicloud Lab Variables

This is the memory sheet for the Terraform + Ansible cloud lab.

## Source Of Truth

Most non-secret settings live in:

```text
terraform/multicloud-vm-yaml-lab/config/lab.yaml
```

Important neutral YAML keys:

| Key | Meaning |
| --- | --- |
| `cloud` | Selects `aws` or `gcp`. |
| `location` | Logical location, translated through `catalog.locations`. |
| `runtime.mode` | Selects `external`, `postgres`, or `cloud-native`. Scripts normalize this to `cloud_native` for containers. |
| `runtime.sessions.backend` | For cloud-native this should be `managed_valkey`. |
| `secrets.prefix` | Prefix/name namespace for cloud secret manager entries. |
| `secrets.items.*` | Neutral secret item names, not secret values. |
| `clouds.aws.profile` | AWS CLI profile used by the AWS provider and lab helper script. |
| `clouds.aws.app_instance_profile_name` | Pre-created EC2 instance profile from the one-time IAM bootstrap. |

Terraform backend state config lives in:

```text
terraform/multicloud-vm-yaml-lab/backend.hcl
```

## Local `.env`

Use local `.env` only as an operator input file:

```bash
cp terraform/multicloud-vm-yaml-lab/examples/env.cloud.example .env
source .env
```

Real `.env` files are ignored by Git. Do not commit passwords or tokens.

| Variable | Used By | Meaning |
| --- | --- | --- |
| `SSH_KEY_PATH` | Ansible | Private key for bastion and private hosts. |
| `DB_PASSWORD` | `secrets push`, current Terraform DB creation | App DB password source. Current Terraform DB modules still receive this as `TF_VAR_db_password`. |
| `RABBITMQ_PASSWORD` | `secrets push` only for `external`/`postgres` | RabbitMQ password for VM/container runtime modes. |
| `GHCR_USERNAME` | Ansible | GHCR login username when packages are private. |
| `GHCR_TOKEN` | `secrets push`, Ansible | GHCR token. Read needs `read:packages`; push needs `write:packages`. |
| `CLOUDFLARE_API_TOKEN` | Terraform Cloudflare provider | DNS record and cert validation records. |
| `AWS_PROFILE` | AWS CLI/Terraform helper | Usually `coinops-lab`. |
| `AWS_REGION` | AWS CLI helper | Usually `eu-central-1`. |
| `GCP_PROJECT_ID` | GCP helper fallback | Optional if YAML already has project id. |

## One-Time AWS Bootstrap

Normal Terraform should not create IAM roles again and again. Run bootstrap once with an admin-capable AWS profile:

```bash
cd terraform/multicloud-vm-yaml-lab
ADMIN_PROFILE=<admin-profile> IAM_USER=terraform-coinops-lab ./aws-iam/bootstrap.sh
```

Bootstrap creates:

```text
AWSServiceRoleForElasticLoadBalancing
AWSServiceRoleForElastiCache
AWSServiceRoleForRDS
coinops-lab-app-runtime-role
coinops-lab-app-runtime-profile
split least-privilege policies for terraform-coinops-lab
```

After this, normal applies use the limited `terraform-coinops-lab` user. The main stack passes the existing app instance profile by name instead of creating IAM roles during every apply.

## Secret Manager Flow

Secrets are named in YAML, but values are pushed from local environment into the selected cloud secret manager.

Normal flow:

```bash
cd terraform/multicloud-vm-yaml-lab
source ../../.env
./scripts/lab.sh doctor
./scripts/lab.sh secrets push
./scripts/lab.sh plan
./scripts/lab.sh apply
./scripts/lab.sh deploy
```

`secrets push` writes:

| YAML item | AWS name example | GCP id example |
| --- | --- | --- |
| `db_password` | `coinops-lab/db-password` | `coinops-lab-db-password` |
| `rabbitmq_password` | `coinops-lab/rabbitmq-password` | `coinops-lab-rabbitmq-password` |
| `ghcr_token` | `coinops-lab/ghcr-token` | `coinops-lab-ghcr-token` |

Terraform creates only secret containers/metadata. Secret values are added by `./scripts/lab.sh secrets push`.

## Generated Files

These are generated locally and should not be committed:

```text
~/.ssh/aws-multicloud-lab.generated
~/.ssh/gcp-multicloud-lab.generated
ansible/inventory.cloud
```

`./scripts/lab.sh apply`, `./scripts/lab.sh outputs`, and `./scripts/lab.sh deploy` regenerate or consume them.

## Current Caveat

The deploy path now fetches runtime secrets from AWS Secrets Manager or GCP Secret Manager. The managed DB Terraform resources still receive `DB_PASSWORD` as `TF_VAR_db_password`, so the DB password may still appear in Terraform state until the DB user/bootstrap flow is moved fully outside Terraform.