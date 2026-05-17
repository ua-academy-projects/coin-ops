# Multi-Cloud Scope

This document defines what "multi-cloud" currently means for `coin-ops` and what remains intentionally asymmetric even after adding Azure parity.

It is a scope document, not a runbook. For operator steps, use [runbook.md](/D:/Internship/coin-ops-local/coin-ops/runbook.md). For architecture context, use [CONTEXT.md](/D:/Internship/coin-ops-local/coin-ops/CONTEXT.md).

## Current Position

The repo supports a **GCP-default production-like path** plus **AWS** and **Azure** parity paths for the infrastructure primitives that are currently in scope.

That means:

- GCP is the default control-plane cloud today.
- AWS and Azure have matching backend storage, compute/network, secret-management, managed PostgreSQL, dynamic inventory, bastion/NAT access, and the same logical topology model.
- `clouds.control_plane` selects the intended state/control-plane workflow; `clouds.secret_backend` selects the runtime secret source read by Ansible.
- Every supported cloud bootstrap should prepare its own Terraform state storage and native lock-safe backend configuration so that the control-plane cloud can be changed intentionally later.
- DNS parity is intentionally out of scope. The root domain belongs to `dns.primary_cloud`; non-primary clouds are validated by public IP.

## Support Matrix

| Capability | GCP | AWS | Azure | Notes |
|------|------|------|------|------|
| Terraform VM/network provisioning | Supported | Supported | Supported | Same logical topology model |
| Dynamic Ansible inventory | Supported | Supported | Supported | `google.cloud.gcp_compute` / `amazon.aws.aws_ec2` / `azure.azcollection.azure_rm` |
| Private-host access through jump host | Supported | Supported | Supported | Generated SSH config + ProxyJump |
| Generated local bootstrap/env workflow | Supported | Supported | Supported | GCS/S3/Azure Storage backend artifacts are generated explicitly |
| Runtime secret retrieval in Ansible | Supported | Supported | Supported | `clouds.secret_backend` selects GCP Secret Manager, AWS Secrets Manager, or Azure Key Vault |
| Managed PostgreSQL path | Supported | Supported | Supported | Cloud SQL on GCP, RDS PostgreSQL on AWS, Flexible Server on Azure |
| Safe compute-only destroy/recreate flow | Supported | Supported | Supported | Compute targets preserve managed DB and secret stores |
| Full stateful teardown helper | Supported | Supported | Supported | Helper removes protections only in a temporary Terraform copy |
| Cloudflare-backed TLS/origin flow | Supported | Potentially usable | Potentially usable | Documented and validated on GCP-first path |

## What "Supported on All Clouds" Means

The following are part of the intended cross-cloud contract:

- the same logical VM roles:
  - `jump-host`
  - `app-1`
  - `app-2`
- the same private-subnet access model through bastion/NAT
- the same dynamic inventory grouping model
- the same same-origin UI topology:
  - `/api`
  - `/history-api`
- the same compose-based deploy model
- the same config-driven instance sizing / region / image mapping approach
- DNS belongs only to `dns.primary_cloud`; non-primary clouds are validated by public IP, not by cloud-specific subdomains.

If a feature falls into this category, we should try to keep behavior conceptually aligned across clouds.

## What Remains Intentionally Asymmetric

The following are intentionally asymmetric today:

- GCP remains the default active `control_plane`.
- DNS is assigned only to `dns.primary_cloud`; AWS and Azure are validated by direct public IP unless selected as primary.
- Full stateful destroy is deliberately opt-in and uses the same helper for GCP, AWS, and Azure.

These are not cloud feature gaps in this phase; they are explicit operational boundaries.

## Cloud Parity Included In This Phase

This phase includes:

- AWS Secrets Manager resources with the same logical secret payloads as GCP.
- Azure Key Vault resources with the same logical secret payloads as GCP.
- AWS RDS PostgreSQL in private subnets with backend-only security group access.
- Azure Database for PostgreSQL Flexible Server with private subnet access.
- Normalized Terraform-to-Ansible database metadata for all supported clouds.
- Ansible secret lookup keyed by `clouds.secret_backend`.
- AWS bootstrap permissions for S3 state, EC2/VPC, RDS, and Secrets Manager.
- Azure bootstrap permissions for Azure Storage state, VNet/VM resources, PostgreSQL, and Key Vault.

## Managed-Service Strategy Boundary

For now:

- PostgreSQL managed service parity is a real target.
- RabbitMQ and Redis managed replacements are still strategy/research items, not implementation commitments.

That means:

- AWS Secrets Manager, Azure Key Vault, and managed PostgreSQL are implemented parity targets.
- SQS, ElastiCache, Azure-native replacements, and GCP equivalents remain later-phase design work unless promoted intentionally.

## Success Criteria For Phase D

This parity phase can be considered complete only when:

- the repo documents exactly which workflows are supported on GCP, AWS, and Azure
- AWS and Azure secret-management parity are implemented and validated
- AWS and Azure managed-database strategies are implemented and validated
- operator docs stop implying full cloud symmetry where it does not exist

The honest repo statement after this phase is:

> `coin-ops` supports a GCP-default infrastructure path plus AWS and Azure parity paths for state backend storage, secrets, managed PostgreSQL, network, compute, inventory, and deploy runtime. DNS remains primary-cloud-only.
