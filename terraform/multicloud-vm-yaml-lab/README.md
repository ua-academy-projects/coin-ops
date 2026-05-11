# Multicloud VM YAML Lab

One Terraform root and one neutral YAML config create the same logical lab on AWS or GCP.

Switch target cloud in:

```yaml
# config/lab.yaml
cloud: aws
# or
cloud: gcp
```

## Active Layout

```text
.
в”њв”Ђв”Ђ config/                  # neutral YAML input
в”њв”Ђв”Ђ scripts/                 # lab UX: plan/apply/deploy/secrets/doctor
в”њв”Ђв”Ђ aws-iam/                 # one-time AWS bootstrap and limited IAM policies
в”њв”Ђв”Ђ docs/                    # notes and variable memory sheets
в”њв”Ђв”Ђ examples/                # local example files, no real secrets
в”њв”Ђв”Ђ modules/
в”‚   в”њв”Ђв”Ђ aws-cloud-native/    # AWS provider stack orchestrator
в”‚   в”њв”Ђв”Ђ gcp-stack/           # GCP provider stack orchestrator
в”‚   в”њв”Ђв”Ђ shared/              # modules used by both/provider stacks
в”‚   в”‚   в”њв”Ђв”Ђ access-outputs/
в”‚   в”‚   в”њв”Ђв”Ђ aws-secrets/
в”‚   в”‚   в””в”Ђв”Ђ gcp-secrets/
в”‚   в””в”Ђв”Ђ _archive/legacy/     # old VM-only modules kept for reference
в””в”Ђв”Ђ archive/                 # old helper scripts and Windows sidecar files
```

## Config Flow

```text
config/lab.yaml
  -> locals.raw
  -> local.config     # YAML merged with defaults
  -> local.stack      # normalized provider-ready intent
  -> module.aws or module.gcp
```

There is no separate `locals.intent.tf` anymore. `local.stack` is the current intent object.

## Normal Commands

```bash
cd ~/projects/softserv-internship/terraform/multicloud-vm-yaml-lab

./scripts/lab.sh doctor
./scripts/lab.sh secrets push
./scripts/lab.sh plan
./scripts/lab.sh apply
./scripts/lab.sh deploy
```

AWS IAM bootstrap is one-time only:

```bash
ADMIN_PROFILE=coinops-admin IAM_USER=terraform-coinops-lab ./aws-iam/bootstrap.sh
```

## Secrets

YAML stores secret names only. Secret values are pushed separately into AWS Secrets Manager or GCP Secret Manager.

See:

```text
docs/VARIABLES.md
examples/env.cloud.example
```