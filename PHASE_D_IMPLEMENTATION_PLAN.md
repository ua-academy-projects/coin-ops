# Phase D Implementation Plan: AWS Parity with the GCP-First Path

This document turns Phase D into a staged implementation plan for AWS parity with the current GCP-first path. The goal is not one-shot “full symmetry.” GCP remains the reference implementation, and AWS parity means aligning operator workflow and infrastructure behavior where that alignment is worth the maintenance cost. This phase focuses only on the missing AWS runtime and lifecycle pieces, not on redoing already-complete inventory, bootstrap, or config-structure work from earlier phases.

## Current Baseline

The repo already supports the following on both clouds:

- Terraform VM and network topology for `jump-host`, `app-1`, and `app-2`
- dynamic cloud inventory
- ProxyJump/private-host access through the bastion model
- same-origin UI routing through the public gateway
- config-driven topology, size, region, and image mapping

The following are still GCP-only today:

- runtime secret retrieval in Ansible through GCP Secret Manager
- managed PostgreSQL through Cloud SQL
- validated stateful-resource lifecycle and full-destroy flow
- the complete proven bootstrap and deploy workflow

Phase D starts from **AWS partial parity**, not from zero infrastructure.

## Target Parity Contract

Phase D is complete when both clouds support the same logical operator flow:

1. bootstrap the local environment
2. provision infrastructure
3. deploy with Ansible
4. consume runtime secrets without repo `.env`
5. support safe compute-only destroy and recreate

Both clouds must continue to support the same logical VM roles:

- `jump-host`
- `app-1`
- `app-2`

Both clouds must continue to use the same high-level deploy contract:

- compose-based workloads
- dynamic inventory and bastion access
- stable layered config structure

Phase D parity does **not** require:

- identical provider resources
- identical secret-service names
- managed RabbitMQ or managed Redis
- deeper cross-cloud abstraction beyond current operator needs

Defaults locked for this phase:

- managed PostgreSQL parity is in scope
- managed RabbitMQ and managed Redis are out of scope

## Stage 1: AWS Runtime Secret-Management Parity

This is the first active implementation stage because it closes the biggest functional gap between AWS and the working GCP deploy path.

### Implementation decisions

- Use **AWS Secrets Manager** as the AWS runtime secret source.
- Keep the same secret grouping model as GCP:
  - one DB/runtime secret bundle:
    - `DB_PASSWORD`
    - `RABBITMQ_PASSWORD`
  - one app/integration secret bundle:
    - `GHCR_TOKEN`
    - `CLOUDFLARE_API_TOKEN`
- Keep the same Ansible behavior:
  - retrieve secrets at deploy time
  - do not reintroduce repo `.env`
  - fail closed if required secrets are missing
- Extend the Ansible composition layer so secret lookup is keyed by `my_cloud`.
- Preserve current GCP Secret Manager behavior unchanged.

### Required implementation changes

- Terraform must create AWS Secrets Manager secret containers and current versions using the same seed/rotation concept already used on GCP.
- Normal Terraform and Ansible runs must not require exported secret values after the initial seed or explicit rotation workflow.
- AWS bootstrap and secret rotation must remain explicit operator actions, not implicit on every `terraform apply`.
- AWS secret names must follow a repo-consistent naming scheme analogous to:
  - `coinops-db-secrets`
  - `coinops-app-secrets`
- AWS Ansible secret retrieval must not depend on ad hoc local files on the controller.

### Success criteria

- AWS Ansible deploy retrieves required secrets from AWS Secrets Manager
- missing AWS secrets fail early with clear errors
- GCP deploy behavior is unchanged
- no repo `.env` is required for AWS runtime deploys

## Stage 2: AWS Managed PostgreSQL Parity

This stage adds the managed DB equivalent to the current Cloud SQL path.

### Implementation decisions

- Use **Amazon RDS for PostgreSQL** as the AWS managed database target.
- Keep the same application/runtime contract:
  - Ansible receives managed DB metadata through the narrow runtime handoff
  - `use_managed_db` is true when the managed DB path is enabled
  - `RUNTIME_BACKEND=postgres` with managed DB remains unsupported unless explicitly redesigned later
- Keep the same topology expectation:
  - DB is private-only
  - backend services on `app-2` connect over private networking
- Keep the Terraform→Ansible handoff narrow and non-host-oriented.

### Required implementation changes

- Terraform must provision AWS DB networking and RDS instance resources.
- Runtime metadata generation must include only the AWS managed DB data Ansible actually needs.
- Security groups, subnet groups, and private routing must align with the current private-subnet model.
- Compute-only destroy must preserve the managed DB by default.
- AWS DB password must come from AWS Secrets Manager, not repo config or controller env files.

### Success criteria

- AWS backend deploy can use managed PostgreSQL without local Postgres on `app-2`
- Terraform and Ansible contract remains narrow and understandable
- GCP Cloud SQL path remains unchanged
- unsupported runtime combinations still fail early

## Stage 3: AWS Bootstrap and Operator-Flow Parity

This stage aligns the AWS operator experience with the current GCP-first workflow.

### Implementation decisions

- Refactor `terraform/bootstrap-aws.sh` to match the generated-local-file pattern already used by GCP.
- Generate the same kinds of local operator artifacts where applicable:
  - generated local env script
  - local non-secret Terraform config
  - local non-secret Ansible config
  - bootstrap secret template for initial seeding and later rotation
- Keep AWS bootstrap values sourced from committed config/templates, not a repo `.env`.
- Preserve the shared config structure already introduced in earlier phases:
  - `terraform/config/config.json`
  - `terraform/config/cloud_mappings.json`
  - committed bootstrap defaults file(s)

### Target operator model

AWS must converge on the same conceptual operator flow:

1. bootstrap once
2. source generated env
3. seed secrets if needed
4. run `terraform apply`
5. run `ansible provision.yml`
6. run `ansible deploy.yml`

### Success criteria

- AWS no longer behaves like a one-off bootstrap path
- operator docs can describe one conceptual workflow with cloud-specific details
- local generated files remain gitignored and clearly bounded

## Stage 4: Stateful Lifecycle Parity for AWS

This stage brings AWS to the same behavioral lifecycle guarantees as the current GCP path.

### Implementation decisions

- AWS managed DB and AWS secrets must be protected from casual destroy by default.
- Compute-only destroy and recreate must remain the easy operator path.
- Intentional full teardown must be possible only through an explicit operator flow.
- Behavioral parity is required; identical provider mechanics are not.
- Preferred implementation approach:
  - extend the existing temporary-copy full-destroy helper pattern to AWS-managed stateful resources

### Required implementation changes

- Add AWS-side destroy protections for managed DB and AWS secrets.
- Extend the deliberate full-destroy helper so it can strip AWS-side protections in the temporary Terraform copy only.
- Keep GCP helper behavior intact while expanding it for AWS.
- Document the AWS full-destroy path in `runbook.md` once implemented and validated.

### Success criteria

- AWS managed DB and secrets survive normal destroy flows unless intentionally removed
- AWS full teardown has one explicit documented path
- GCP and AWS lifecycle documentation no longer diverges conceptually

## Stage 5: Docs and Support-Matrix Convergence

This is the closing stage and should happen only after the earlier implementation stages are complete or intentionally deferred.

### Required documentation changes

- Update `MULTI_CLOUD_SCOPE.md` from “partial parity” to the new supported reality
- Update `CONTEXT.md` so AWS support statements reflect actual implementation
- Update `runbook.md` so AWS operator steps are documented as a first-class path where appropriate
- Keep claims precise:
  - no vague “fully multi-cloud” language
  - no implied parity for managed RabbitMQ or managed Redis

### Success criteria

- support claims are accurate
- operators can understand supported cloud behavior without reading Terraform code
- docs do not imply parity before implementation exists

## Locked Decisions and Interfaces

The following decisions are fixed for this phase and should not be re-decided during implementation:

- **Parity model:** staged, not one-shot
- **AWS secret manager:** AWS Secrets Manager
- **AWS managed DB:** Amazon RDS for PostgreSQL
- **Runtime secret retrieval:** Ansible at deploy time, not repo `.env`
- **Managed RabbitMQ/Redis:** out of scope
- **Terraform→Ansible handoff:** narrow, non-VM runtime metadata only
- **Lifecycle protection target:** behavioral parity with GCP, not identical provider mechanics
- **Operator workflow goal:** one conceptual bootstrap/apply/deploy flow on both clouds

## Validation Plan

### AWS secret-management validation

- seed AWS secrets
- verify Ansible retrieves them during deploy
- verify missing secrets fail clearly
- verify GCP secret-retrieval behavior remains unchanged

### AWS managed DB validation

- confirm private connectivity from `app-2` to the RDS endpoint
- verify deploy succeeds without local Postgres when managed DB is enabled
- verify unsupported runtime combinations fail early

### AWS lifecycle validation

- verify compute-only destroy preserves managed DB and secrets
- verify explicit full teardown removes protected AWS stateful resources only when deliberately invoked

### Cross-cloud regression validation

- GCP Terraform/apply/deploy still succeeds
- GCP Secret Manager and Cloud SQL paths remain intact
- shared config/mapping/bootstrap structure remains understandable and usable

## Assumptions

- GCP remains the reference implementation throughout Phase D
- AWS parity is worth pursuing only where it preserves a coherent operator experience
- parity means equivalent behavior, not identical provider resources
- managed RabbitMQ and managed Redis are not part of this implementation plan
- the existing config, inventory, and bootstrap structure from Phases A-C should be preserved rather than redesigned
