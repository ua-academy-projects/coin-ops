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

The first version of this phase is implemented: the repo now has a deliberate full-destroy helper that tears down protected resources from an isolated temporary Terraform copy instead of requiring direct module edits. The remaining work in this phase is to validate and harden that operator path.

### Goals

- preserve the current safety model for DB and secrets
- keep the new destroy-helper path dependable and well-bounded
- make compute-only destroy/recreate the easy default path

### Work Items

1. Validate the dedicated full-destroy helper end to end.
   - Test the temporary-copy approach against the real backend state in a controlled environment.
   - Confirm it reliably removes the stateful protections only in the ephemeral working copy.
   - Confirm operator local files and backend configuration are preserved outside the teardown target.

2. Define the supported destroy/recreate workflows precisely.
   - Safe compute-only destroy and recreate.
   - Normal day-to-day apply/update flow.
   - Full teardown of everything, including stateful infrastructure, through an intentional process.

3. Harden the long-term lifecycle architecture if needed.
   - Evaluate whether separate Terraform state for compute versus stateful resources would be cleaner than the helper-based approach.
   - Evaluate whether separate root stacks or orchestration layers would reduce operational risk further.
   - Keep these as architecture follow-ups, not prerequisites for using the current helper.

4. Keep operator documentation exact.
   - Ensure `runbook.md` remains decision-complete for destroy and rebuild operations.
   - Document known limitations of the helper-based approach so operators do not make hidden assumptions.

### Success Criteria

- normal destroy/recreate of compute is easy and documented
- stateful infrastructure remains protected by default
- full teardown is possible through an intentional operator flow, not ad hoc file edits
- the destroy-helper workflow is validated and documented well enough for repeated use

## Phase C: Config and Inventory Architecture Refinement

The first slice of this phase is implemented: backend host discovery now comes from inventory instead of Terraform handoff, cloud-specific sizes/regions/images are consolidated in `terraform/config/cloud_mappings.json`, and committed bootstrap/deploy/DNS defaults now live in split SSOT JSON files under `terraform/config/`. The remaining work in this phase is to simplify and harden that structure further without reopening the migration.

### Goals

- reduce residual coupling between Terraform internals and Ansible runtime behavior
- keep inventory responsible for host discovery and connectivity
- keep stable deploy policy in committed non-secret config

### Work Items

1. Keep Terraform-to-Ansible coupling narrow and intentional.
   - Preserve `terraform/config/ansible-runtime.json` only for non-VM infrastructure metadata that inventory cannot discover cleanly.
   - Revisit whether the remaining managed-DB metadata can be represented even more clearly without expanding the handoff again.

2. Keep generated host artifacts as debug/operator outputs only.
   - Preserve `hosts.json` and similar files as convenience artifacts, not runtime sources of truth.
   - Ensure no Ansible path drifts back toward using generated host JSON as inventory logic.

3. Move only inventory-native derivation into inventory configuration.
   - Use inventory `compose` or a follow-up constructed source for host-local connection facts and grouping logic when that clearly improves clarity.
   - Do not move deploy-policy logic or secret retrieval into inventory just to reduce file count.

4. Refine the consolidated cloud config structure.
   - Keep using dictionary-style mappings for cloud-specific images, AMI/image selectors, regions, and similar provider metadata.
   - Review whether the current logical-region and image-profile model is expressive enough for future cloud additions without becoming too abstract.
   - Keep the result readable; the goal is to reduce drift and duplication, not to hide cloud-specific differences.

5. Reassess bootstrap-default ownership.
   - Keep bootstrap-local generated files small and operator-oriented rather than letting them become a second full infrastructure config.
   - Decide carefully which values belong in generated local artifacts versus the committed split JSON files under `terraform/config/`.
   - Preserve the generated-local-file model and avoid reintroducing duplicated sources of truth.

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

The first slice of this phase is implemented on the GCP path: the repo has Packer templates for an app-host golden image, and `app-1` / `app-2` can use the `coinops-app-host` profile while `jump-host` remains on the base Debian image.

### Goals

- shorten provisioning time
- reduce per-VM setup variance
- keep runtime deployment logic cleanly separated from base-image preparation

### Work Items

1. Evaluate a base-image pipeline.
   - Compare Packer with other image-build approaches suitable for GCP and AWS.
   - Focus on preinstalling Docker, common dependencies, user hardening, and baseline OS setup.
   - Prioritize VM roles that actually run containers, since those benefit most from pre-baked Docker and host hardening.
   - Start with a shared `app-host` image for `app-1` and `app-2` before considering a separate `jump-host` image.
   - Treat the current GCP app-host rollout as the reference slice before repeating it on AWS.

2. Define the image-versus-Ansible boundary.
   - Decide what belongs in a golden image versus what must remain in Ansible because it changes often.
   - Keep service deployment, runtime env wiring, and compose rendering in the Ansible deploy path.
   - Avoid creating per-VM templates unless the operational benefit clearly exceeds the maintenance cost.
   - Continue shrinking app-host provisioning only after baked behavior is validated, while keeping `jump-host` on the full path.
   - Prefer explicit validation of baked host assumptions over silently reinstalling image-provided tooling on app hosts.

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
