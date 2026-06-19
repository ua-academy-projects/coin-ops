# Coin-Ops Infrastructure

This repository contains the deployment infrastructure for Coin-Ops. Application images are pulled from GHCR; app source, local app builds, app tests, and smoke stacks are not kept here.

## What This Repo Owns

| Path | Purpose |
| --- | --- |
| `terraform/` | Cloud resources, EKS/Jenkins, remote-state bootstrap, networking, Cloudflare, secrets, observability |
| `ansible/` | Active EKS workloads, legacy VM/k3s provisioning, runtime config materialization |
| `deploy/compose/` | Jinja Docker Compose templates rendered by Ansible on VM targets |
| `deploy/sql/` | Retained PostgreSQL history/runtime bootstrap SQL used by infra deploys |
| `deploy/postgres-runtime/` | PostgreSQL 16 runtime image with `pg_cron` and `pgmq` |
| `packer/` | Optional golden-image build definitions for pre-baked app hosts |
| `docs/` | Operator runbooks |

## Deployment Model

The active recovery target is AWS EKS:

- Terraform creates AWS networking, EKS, IAM, Secrets Manager, Cloudflare
  resources, Jenkins, and CloudWatch observability.
- Jenkins runs dynamic Kubernetes agents and invokes Ansible through separate
  Headlamp and CoinOps jobs.
- Headlamp and Jenkins use Cloudflare Tunnel/Access. CoinOps uses public
  Traefik ingress with fixed AWS EIPs and public Cloudflare A records.

VM Compose and self-managed k3s code remains for historical/multicloud support,
but is not part of the active AWS rebuild sequence. Start with `runbook.md`
before operating a previously destroyed environment.

## Runtime Modes

- `RUNTIME_BACKEND=postgres`: normal mode. PostgreSQL runtime SQL enables `pgmq`, queue wrappers, cache/session tables, and `pg_cron` cleanup jobs.
- `RUNTIME_BACKEND=external`: rollback mode. RabbitMQ and Redis remain available in the VM Compose templates.

Runtime SQL lives under `deploy/sql/` because it is a database bootstrap asset required by infrastructure, not application source.

## Operator Quick Start

For a rebuild from zero, do not use this abbreviated section; follow
`runbook.md` in order.

```bash
cd /home/notebook/projects/coin-ops
source local/generated-env.sh
make tf-check-backend
make runtime-config
```

Run static checks:

```bash
cd /home/notebook/projects/coin-ops
make ci-validate
```

Apply infrastructure locally only when intentionally bypassing the managed
pipeline:

```bash
make tf-plan
make tf-apply
```

Deploy the active EKS workloads after Terraform has created the cluster and
generated the local kubeconfig:

```bash
make eks-headlamp
make eks-coinops
```

The normal post-bootstrap path runs those reconciliations through the Jenkins
jobs `coinops-eks-deploy-headlamp` and `coinops-eks-deploy-coinops`.

Build the PostgreSQL runtime image when its Dockerfile changes:

```bash
docker build -t coin-ops-postgres-runtime -f deploy/postgres-runtime/Dockerfile deploy/postgres-runtime
```

## Configuration

Canonical non-secret configuration is split across `terraform/config/*.json`:

- `clouds.json`: enabled clouds, control plane, secret backend, provider account metadata
- `general.json`: project name, region profile, username, SSH port, base image profile
- `instances.json`: VM layout and roles
- `networks.json`: VPC/VNet CIDRs, subnets, firewall rules, Tailscale route policy
- `deploy.json`: image registry/tag, TLS, runtime backend, k3s app settings
- `database.json`: database engine and cloud profiles
- `dns.json`: Cloudflare zone/account and DNS defaults
- `secrets.json`: secret manager object names

Terraform writes local files such as `terraform/config/hosts.json`, `terraform/config/ssh_config`, and `terraform/config/ansible-runtime.json`. Ansible `runtime_config` merges config, generated data, environment overrides, and secrets.

## Generated Files and Secrets

Do not commit:

- `terraform/backend.active.tf`
- `terraform/local.generated.auto.tfvars.json`
- `terraform/config/hosts.json`
- `terraform/config/ssh_config`
- `terraform/config/ansible-runtime.json`
- `terraform/sa-key.json`
- `ansible/vars/local.generated.json`
- `ansible/artifacts/`
- `local/generated-*.sh`
- tfstate, kubeconfigs, private keys, and cloud credentials

## Runbooks

- `runbook.md`: complete AWS rebuild, acceptance, operations, and teardown;
- `docs/aws-codebuild-k3s.md`: AWS CodePipeline/CodeBuild details (legacy
  filename, active Terraform pipeline);
- `docs/aws-eks-jenkins.md`: EKS, Jenkins, Ansible, and workload operations;
- `docs/github-actions-validation.md`: validation and GitHub OIDC trigger;
- `terraform/README.md`: Terraform repair and destroy mechanics.

Multicloud, Tailscale, Cloudflare DNS/Access, Headlamp, Homepage, CNPG, VM
Compose, and k3s remain repository concerns. Do not add app source directories
or direct browser calls to backend private IPs.
