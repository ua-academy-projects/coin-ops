# Multi-Cloud Scope

This document defines what "multi-cloud" currently means for `coin-ops` and what is still intentionally GCP-first.

It is a scope document, not a runbook. For operator steps, use [runbook.md](/D:/Internship/coin-ops-local/coin-ops/runbook.md). For architecture context, use [CONTEXT.md](/D:/Internship/coin-ops-local/coin-ops/CONTEXT.md).

## Current Position

The repo supports a **GCP-first production-like path** and a **partial AWS parity path**.

That means:

- GCP is the primary supported cloud for the full bootstrap, secret-management, managed-database, TLS, and deploy workflow.
- AWS support currently covers compute/network provisioning patterns, dynamic inventory, bastion/NAT access, and the same logical topology model.
- "Multi-cloud" does not currently mean identical features, identical destroy flows, or identical secret/managed-service integrations across both providers.

## Support Matrix

| Capability | GCP | AWS | Notes |
|------|------|------|------|
| Terraform VM/network provisioning | Supported | Supported | Same logical topology model |
| Dynamic Ansible inventory | Supported | Supported | `google.cloud.gcp_compute` / `amazon.aws.aws_ec2` |
| Private-host access through jump host | Supported | Supported | Generated SSH config + ProxyJump |
| Generated local bootstrap/env workflow | Supported | Partial | AWS bootstrap exists, but is less complete than GCP |
| Runtime secret retrieval in Ansible | Supported | Not implemented | GCP Secret Manager only today |
| Managed PostgreSQL path | Supported | Not implemented | Cloud SQL only today |
| Safe compute-only destroy/recreate flow | Supported | Mostly aligned | Stateful-resource protections are defined around GCP path today |
| Full stateful teardown helper | Supported | GCP-focused | Current helper removes GCP stateful protections |
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

If a feature falls into this category, we should try to keep behavior conceptually aligned across clouds.

## What Remains GCP-First

The following are intentionally GCP-first today:

- Secret Manager as the runtime secret source for Ansible
- managed PostgreSQL through Cloud SQL
- the full bootstrap path for seeding secrets and then running normal deploys
- the validated stateful-resource protection and deliberate full-destroy helper flow

These are not AWS bugs in the current phase; they are explicit scope limits.

## AWS Gaps That Are Real Phase D Work

These are the concrete AWS-side gaps still pending:

1. Runtime secret-management parity.
   - AWS needs a supported equivalent to the current GCP Secret Manager lookup flow.
   - The target should be an Ansible runtime retrieval path, not a return to repo `.env`.

2. Managed-database parity.
   - AWS needs an explicit decision on RDS or another managed PostgreSQL path.
   - The result should include runtime integration, protection expectations, and destroy/rebuild rules.

3. Bootstrap parity.
   - `terraform/bootstrap-aws.sh` exists, but the operator experience is not yet as complete and validated as GCP.
   - The repo should not imply otherwise.

4. Stateful lifecycle parity.
   - Current stateful protection and deliberate full destroy are designed around GCP stateful resources.
   - AWS equivalents should only be claimed after they exist and are tested.

## Managed-Service Strategy Boundary

For now:

- PostgreSQL managed service parity is a real target.
- RabbitMQ and Redis managed replacements are still strategy/research items, not implementation commitments.

That means:

- AWS Secrets Manager and managed PostgreSQL are Phase D implementation candidates.
- SQS, ElastiCache, and GCP equivalents remain later-phase design work unless promoted intentionally.

## Success Criteria For Phase D

Phase D can be considered complete only when:

- the repo documents exactly which workflows are supported on GCP and AWS
- AWS secret-management parity is either implemented or explicitly deferred with rationale
- AWS managed-database strategy is decided and documented
- operator docs stop implying full cloud symmetry where it does not exist

Until then, the honest repo statement is:

> `coin-ops` supports a full GCP-first infrastructure path and a partial AWS parity path.

