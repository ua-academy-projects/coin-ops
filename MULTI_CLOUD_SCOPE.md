# Multi-Cloud Scope

This document defines what "multi-cloud" currently means for `coin-ops` and what is still intentionally GCP-first.

It is a scope document, not a runbook. For operator steps, use [runbook.md](/D:/Internship/coin-ops-local/coin-ops/runbook.md). For architecture context, use [CONTEXT.md](/D:/Internship/coin-ops-local/coin-ops/CONTEXT.md).

## Current Position

The repo supports a **GCP-default production-like path** and an **AWS parity path** for the infrastructure primitives that are currently in scope. The file layout and bootstrap contract are prepared for a future Azure path, but Azure resources are intentionally out of scope for the current implementation.

That means:

- GCP is the default control-plane cloud today.
- AWS has matching backend storage, compute/network, secret-management, managed PostgreSQL, dynamic inventory, bastion/NAT access, and the same logical topology model.
- `clouds.control_plane` selects the intended state/control-plane workflow; `clouds.secret_backend` selects the runtime secret source read by Ansible.
- Every supported cloud bootstrap should prepare its own Terraform state storage and native lock-safe backend configuration so that the control-plane cloud can be changed intentionally later.
- Future Azure support must include Azure Storage for state, Azure RBAC/IAM bootstrap, Key Vault, dynamic inventory, VM/network modules, and managed PostgreSQL parity before it is documented as supported.
- DNS parity is intentionally out of scope. The root domain belongs to `dns.primary_cloud`; non-primary clouds are validated by public IP.

## Support Matrix

| Capability | GCP | AWS | Notes |
|------|------|------|------|
| Terraform VM/network provisioning | Supported | Supported | Same logical topology model |
| Dynamic Ansible inventory | Supported | Supported | `google.cloud.gcp_compute` / `amazon.aws.aws_ec2` |
| Private-host access through jump host | Supported | Supported | Generated SSH config + ProxyJump |
| Generated local bootstrap/env workflow | Supported | Supported | GCS/S3 backend artifacts are generated explicitly |
| Runtime secret retrieval in Ansible | Supported | Supported | `clouds.secret_backend` selects GCP Secret Manager or AWS Secrets Manager |
| Managed PostgreSQL path | Supported | Supported | Cloud SQL on GCP, RDS PostgreSQL on AWS |
| Safe compute-only destroy/recreate flow | Supported | Supported | Compute targets preserve managed DB and secret stores |
| Full stateful teardown helper | Supported | Supported | Helper removes GCP/AWS protections only in a temporary Terraform copy |
| Cloudflare-backed TLS/origin flow | Supported | Potentially usable | Documented and validated on GCP-first path |

## What "Supported on Both Clouds" Means

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
- DNS is assigned only to `dns.primary_cloud`; AWS is validated by direct public IP unless selected as primary.
- Full stateful destroy is deliberately opt-in and uses the same helper for GCP and AWS.

These are not AWS feature gaps in this phase; they are explicit operational boundaries.

## AWS Parity Included In This Phase

This phase includes:

- AWS Secrets Manager resources with the same logical secret payloads as GCP.
- AWS RDS PostgreSQL in private subnets with backend-only security group access.
- Normalized Terraform-to-Ansible database metadata for both clouds.
- Ansible secret lookup keyed by `clouds.secret_backend`.
- AWS bootstrap permissions for S3 state, EC2/VPC, RDS, and Secrets Manager.

## Managed-Service Strategy Boundary

For now:

- PostgreSQL managed service parity is a real target.
- RabbitMQ and Redis managed replacements are still strategy/research items, not implementation commitments.

That means:

- AWS Secrets Manager and managed PostgreSQL are implemented parity targets.
- SQS, ElastiCache, and GCP equivalents remain later-phase design work unless promoted intentionally.

## Success Criteria For Phase D

This parity phase can be considered complete only when:

- the repo documents exactly which workflows are supported on GCP and AWS
- AWS secret-management parity is implemented and validated
- AWS managed-database strategy is implemented with RDS PostgreSQL and validated
- operator docs stop implying full cloud symmetry where it does not exist

The honest repo statement after this phase is:

> `coin-ops` supports a GCP-default infrastructure path and an AWS parity path for state backend storage, secrets, managed PostgreSQL, network, compute, inventory, and deploy runtime. DNS remains primary-cloud-only.
