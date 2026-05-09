# Next Phase Plan

This document tracks the remaining infrastructure roadmap after the current GCP-first refactor. It intentionally excludes work that is already implemented, such as dynamic cloud inventory, ProxyJump access to private hosts, GCP Secret Manager runtime integration, generated bootstrap/local config flow, Cloudflare-backed TLS with external port `80` closed, Cloud SQL integration, and the current default protection of stateful resources.

It also assumes the following decisions are already accepted and should not be re-litigated in future phases:

- DNS-based certificate issuance is preferred over opening public HTTP for ACME
- Certbot should stay containerized rather than being reintroduced through host package installation
- origin traffic should remain HTTPS-oriented, with no return to HTTP-only operator flows
- public port `80` stays closed unless an explicit future redesign changes the ingress model

## Current Baseline

The current known-good baseline is:

- infrastructure provisions and deploys successfully on GCP
- origin HTTPS works and is intended to sit behind Cloudflare proxy
- the normal operator workflow is `bootstrap -> source generated env -> terraform apply -> ansible provision/deploy`
- repo `.env` is no longer the standard workflow
- GCP is the primary supported cloud, while AWS remains partial parity

This roadmap starts from that state and focuses only on the remaining work.

## Phase A: Stabilization and Cleanup

This is the first active phase because it reduces operational friction in the current working setup and makes later improvements safer.

### Goals

- prove that the current workflow is repeatable and predictable
- remove transitional leftovers from the earlier migration
- keep the working architecture while simplifying non-essential config logic

### Work Items

1. Verify idempotency of the full operator flow.
   - Run `terraform apply` against an already-provisioned environment and confirm that drift is either absent or understood.
   - Re-run `ansible/provision.yml` and `ansible/deploy.yml` and confirm they are idempotent in practice, not just by design.
   - Record any expected non-idempotent behaviors and either fix them or document them explicitly.

2. Remove stale transition artifacts from repo-tracked config and docs.
   - Search for remaining `.env`-oriented instructions, comments, or assumptions and either delete or rewrite them.
   - Remove outdated comments that still describe the old inventory model, the old deploy contract, or pre-refactor TLS/network assumptions.
   - Check that `runbook.md`, `CONTEXT.md`, and operator-facing comments all describe the same current workflow.

3. Reduce non-essential logic in `group_vars` without breaking the current working behavior.
   - Keep `group_vars` focused on stable deploy policy, bootstrap overlays, Secret Manager lookups, and narrow runtime composition.
   - Identify logic that is purely connection- or inventory-native and is better expressed in inventory `compose` or a constructed layer.
   - Avoid a rewrite for its own sake; the goal is smaller and clearer logic, not another migration.

4. Audit local/generated artifacts and their boundaries.
   - Reconfirm which files are generated and local-only versus which belong in git.
   - Ensure `.gitignore`, `runbook.md`, and `CONTEXT.md` describe the same artifact boundaries.
   - Make sure examples exist where useful and that local-only generated files are not treated as committed inputs.

5. Review bootstrap defaults in `terraform/bootstrap-gcp.sh`.
   - Decide which values should remain intentionally local to the operator environment.
   - Decide which values should move to a committed template or config source if they are not truly machine-local.
   - Preserve the generated bootstrap flow and avoid reintroducing repo `.env` or repeated manual export steps.

### Success Criteria

- a fresh WSL shell can follow the documented workflow without ambiguity
- repeated Terraform and Ansible runs are operationally predictable
- repo docs and comments no longer contradict the current implementation
- generated/local artifacts are clearly separated from committed configuration

## Phase B: Safer Stateful-Resource Lifecycle

This phase addresses the biggest remaining ergonomic gap: safe default protection exists, but complete teardown is still awkward.

### Goals

- preserve the current safety model for DB and secrets
- remove the need for ad hoc code editing when a full teardown is intentionally required
- make compute-only destroy/recreate the easy default path

### Work Items

1. Redesign the full-destroy workflow.
   - Replace the current manual “edit module code to remove protection” flow with a cleaner operator model.
   - Keep accidental destruction of Secret Manager and managed DB resources difficult by default.

2. Evaluate explicit lifecycle architecture options.
   - Separate Terraform state for compute versus stateful resources.
   - Separate root stacks or orchestration layers for stateful modules.
   - A deliberate documented teardown path built around isolated state boundaries rather than live code edits.

3. Define the supported destroy/recreate workflows.
   - Safe compute-only destroy and recreate.
   - Normal day-to-day apply/update flow.
   - Full teardown of everything, including stateful infrastructure, through an intentional process.

4. Update operator documentation once the model is chosen.
   - Reflect the chosen design in `runbook.md`.
   - Keep the destroy guidance decision-complete so an operator does not need to infer what is safe.

### Success Criteria

- normal destroy/recreate of compute is easy and documented
- stateful infrastructure remains protected by default
- full teardown is possible through an intentional operator flow, not ad hoc file edits

## Phase C: Config and Inventory Architecture Refinement

This phase should refine the current split rather than replace it.

### Goals

- reduce residual coupling between Terraform internals and Ansible runtime behavior
- keep inventory responsible for host discovery and connectivity
- keep stable deploy policy in committed non-secret config

### Work Items

1. Reduce Terraform-to-Ansible coupling where it is not strictly necessary.
   - Keep `terraform/config/ansible-runtime.json` narrow and intentional.
   - Revisit whether every current value in the runtime handoff is truly needed or whether some can be derived more cleanly.

2. Keep generated host artifacts as debug/operator outputs only.
   - Preserve `hosts.json` and similar files as convenience artifacts, not runtime sources of truth.
   - Ensure no Ansible path drifts back toward using generated host JSON as inventory logic.

3. Move only inventory-native derivation into inventory configuration.
   - Use inventory `compose` or a follow-up constructed source for host-local connection facts and grouping logic when that clearly improves clarity.
   - Do not move deploy-policy logic or secret retrieval into inventory just to reduce file count.

4. Consolidate cloud config structure where it reduces duplication.
   - Revisit the current split across files like `gcp.json`, `aws.json`, and related provider-specific config inputs.
   - Evaluate a single dictionary-oriented config shape for cloud-specific images, AMI/image selectors, regions, and similar provider metadata.
   - Keep the result readable; the goal is to reduce drift and duplication, not to hide cloud-specific differences.

5. Reassess bootstrap-default ownership.
   - Decide whether bootstrap defaults should continue to live directly in `bootstrap-gcp.sh`.
   - If a template/config file is introduced, keep it small, explicit, and aligned with the generated-local-file model.

6. Keep the architecture constraints explicit.
   - Do not reintroduce heavy dynamic logic into `group_vars`.
   - Do not reintroduce repo `.env` as a central config mechanism.
   - Keep TLS-first behavior across operator and public-facing flows; do not add new HTTP-dependent paths unless there is a strong operational reason.

### Success Criteria

- inventory remains the host/discovery layer
- repo-managed config remains the stable non-secret policy layer
- Terraform runtime handoff stays narrow and understandable
- the bootstrap/config flow is simpler without changing operator behavior unexpectedly

## Phase D: Multi-Cloud Parity and Managed-Service Strategy

This phase collects the medium-term work that is still pending and should not be implied as “already solved”.

### Goals

- define what “multi-cloud parity” really means for this repo
- extend the current GCP-first model only where it is worth the maintenance cost
- make managed-service decisions explicitly rather than by drift

### Work Items

1. Define the actual parity target.
   - Document which behaviors must be supported on both GCP and AWS.
   - Identify which capabilities may remain GCP-first for the foreseeable future.

2. Add AWS runtime secret-management parity if it remains in scope.
   - Design AWS Secrets Manager integration analogous to the current GCP Secret Manager path.
   - Keep the same high-level operator expectations for bootstrap and deploy where practical.

3. Define the AWS managed-database strategy.
   - Decide whether the AWS equivalent should be RDS or another managed PostgreSQL approach.
   - Align destroy, protection, and runtime integration expectations with the GCP Cloud SQL model where feasible.

4. Revisit self-managed versus managed supporting services.
   - Evaluate whether RabbitMQ and Redis should remain containerized on the backend node.
   - If managed replacements are considered, document the required code and deployment impacts before committing to migration.
   - Keep this phase at the strategy level first; moving to managed equivalents should not be treated as an infra-only swap.

5. Keep the scope explicit in docs.
   - Avoid vague “multi-cloud” statements if only partial parity is actually supported.
   - Update operator docs to describe supported paths clearly instead of implying symmetry where it does not exist.

### Success Criteria

- the supported cloud scope is explicit
- secret-management and managed-DB expectations are documented per cloud
- parity claims match the real implementation and support burden

## Phase E: Image and Provisioning Optimization

This is an optimization phase, not a blocker for the current infrastructure.

### Goals

- shorten provisioning time
- reduce per-VM setup variance
- keep runtime deployment logic cleanly separated from base-image preparation

### Work Items

1. Evaluate a base-image pipeline.
   - Compare Packer with other image-build approaches suitable for GCP and AWS.
   - Focus on preinstalling Docker, common dependencies, user hardening, and baseline OS setup.
   - Prioritize VM roles that actually run containers, since those benefit most from pre-baked Docker and host hardening.

2. Define the image-versus-Ansible boundary.
   - Decide what belongs in a golden image versus what must remain in Ansible because it changes often.
   - Keep service deployment, runtime env wiring, and compose rendering in the Ansible deploy path.
   - Avoid creating per-VM templates unless the operational benefit clearly exceeds the maintenance cost.

3. Measure operator benefit.
   - Quantify whether image-based provisioning meaningfully reduces bootstrap/provision time.
   - Prioritize this work only if the time savings and reliability improvements justify the extra build pipeline.

4. Keep the rollout incremental.
   - Do not force a full deployment-model rewrite to adopt base images.
   - Introduce optimization in a way that preserves the current working operator workflow.

### Success Criteria

- provisioning time and variance are reduced in a measurable way
- the division between image build and deploy-time configuration is clear
- the optimization does not destabilize the existing deployment workflow

## Optional Research Track

These items are worth exploring, but they are not implementation-ready next steps and should stay separate from the committed roadmap phases.

### Research Topics

1. Cloudflare Tunnel / Zero Trust
   - Evaluate whether direct public ingress to `app-1` should eventually be replaced with outbound-only tunnel-based access.
   - Assess operational tradeoffs, certificate handling, and compatibility with the current nginx/origin model.
   - Treat this as an optional closed-mode design where 80 and 443 could both be blocked at the infrastructure layer and Cloudflare would expose the endpoint on its side.

2. Managed messaging/cache replacements
   - Explore managed alternatives to RabbitMQ and Redis only if the application and deployment complexity tradeoff is favorable.
   - Treat this as an application-plus-infrastructure design problem, not a drop-in infra swap.
   - Candidate directions include SQS and managed cache products such as ElastiCache or the GCP equivalent, but this remains research-only unless a later phase promotes it.

3. Deeper cross-cloud abstraction
   - Investigate whether further unification of cloud config and orchestration is actually beneficial.
   - Avoid over-abstracting if the operational reality remains GCP-first.

### Research Output Expectations

Each research item should end in one of three decisions:

- promote to an implementation phase
- defer explicitly
- reject as not worth the complexity

## Acceptance Criteria for This Roadmap

This document is correct when:

- every listed phase is still genuinely pending
- completed inventory, secret, TLS, bootstrap, and managed-DB integration work is not listed as future work
- the ordering reflects realistic priorities from the current state
- another engineer can use this roadmap to choose the next implementation phase without reopening the old mentor plan
- the roadmap stays aligned with `CONTEXT.md` and `runbook.md`
