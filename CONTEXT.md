# Coin-Ops Infrastructure Context

This repository is the infrastructure control plane for Coin-Ops. Application source has been removed; deploys pull GHCR image tags configured through `terraform/config/deploy.json`, `IMAGE_REGISTRY`, and `IMAGE_TAG`.

## Ownership Map

| Path | Purpose |
| --- | --- |
| `terraform/` | Cloud resources, EKS/Jenkins, multicloud networking, secret-manager seeding, Cloudflare, observability, generated local files |
| `ansible/` | EKS workloads, legacy host/VM/k3s provisioning, runtime config materialization |
| `deploy/compose/` | Jinja Docker Compose templates rendered by Ansible for VM deploys |
| `deploy/sql/` | PostgreSQL history/runtime bootstrap SQL |
| `deploy/postgres-runtime/` | PostgreSQL runtime image with `pg_cron` and `pgmq` |
| `packer/` | Optional golden-image build definitions for pre-baked app hosts |
| `docs/` | Operator runbooks and architecture notes |

## Active and Legacy Deployment Paths

- Active AWS: Terraform creates EKS and Jenkins; Jenkins dynamic agents run
  `ansible/eks-headlamp.yml` and `ansible/eks-coinops.yml`.
- Legacy VM Compose: `ansible/provision.yml` then `ansible/deploy.yml`.
- Legacy self-managed k3s: `ansible/k3s-platform.yml`,
  `ansible/k3s-homepage.yml`, and `ansible/k3s-coinops.yml`.

All paths consume GHCR application images. None builds app code locally.

## Runtime Modes

- `postgres`: normal mode. PostgreSQL plus `pgmq`/`pg_cron` handles queue and runtime state.
- `external`: rollback mode. RabbitMQ and Redis remain in the Compose templates.

## Networking

- The active AWS path uses private EKS nodes, managed NAT, public Traefik with
  fixed EIPs, and Cloudflare Tunnel/Access for Headlamp and Jenkins.
- Multicloud support remains part of the design.
- Tailscale subnet routing remains supported for gateway-based inter-cloud reachability.
- Cloudflare DNS, Tunnel, and Access remain supported for public and admin entrypoints.
- Frontend traffic stays same-origin through `/api` and `/history-api` reverse proxy paths.

## Configuration Flow

1. Terraform reads split JSON config from `terraform/config/*.json`.
2. Terraform writes local files such as `terraform/config/ansible-runtime.json` and SSH config.
3. Ansible `runtime_config` merges JSON config, generated metadata, optional local overrides, environment overrides, and cloud secret payloads.
4. Jenkins injects the active runtime metadata/secrets into disposable EKS agents.
5. Roles consume the flattened variables and render Compose, nginx, Kubernetes, and SQL bootstrap resources.

## Safety Notes

Generated files such as `terraform/backend.active.tf`, `terraform/local.generated.auto.tfvars.json`, `terraform/config/hosts.json`, `terraform/config/ansible-runtime.json`, `ansible/vars/local.generated.json`, and `ansible/artifacts/` must stay out of commits.

Use `runbook.md` as the canonical full-recovery and operations entry point.
