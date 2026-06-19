# AWS CodePipeline and CodeBuild Terraform Runbook

This runbook manages the active AWS Terraform CI path. The filename, buildspec
filenames, and default resource names retain `k3s` for compatibility, but the
Terraform root now creates the EKS/Jenkins architecture described in
`runbook.md`. VM Compose and Ansible workload deployment are out of scope for
this pipeline.

## Ownership Boundary

Local bootstrap creates the CI control plane:

```text
ci/aws/bootstrap-local.sh
  -> Terraform backend bootstrap via terraform/bootstrap-aws.sh
  -> S3 artifact bucket
  -> SSM SecureString seed parameters
  -> IAM roles and inline policies
  -> CloudWatch log groups
  -> SNS approval notification topic
  -> CodeBuild plan/apply/smoke projects
  -> CodePipeline Source -> Plan -> ApproveApply -> Apply -> Smoke
```

The pipeline uses CodePipeline `QUEUED` execution mode. This prevents newer
executions from overtaking an older execution that is waiting for manual
approval, which reduces stale Terraform saved-plan failures.

CodeBuild runs the workload Terraform plan:

```text
ci/aws/buildspec.k3s-terraform-plan.yml
  -> source ci/aws/codebuild-worker-env.sh
  -> render terraform/backend.active.tf
  -> prune disabled Azure provider wiring for the ephemeral AWS worktree
  -> terraform init
  -> terraform plan
  -> upload terraform/plan.out and terraform/plan.txt
```

After manual approval, a separate CodeBuild project runs Terraform apply:

```text
ci/aws/buildspec.k3s-terraform-apply.yml
  -> source ci/aws/codebuild-worker-env.sh
  -> render terraform/backend.active.tf
  -> prune disabled Azure provider wiring for the ephemeral AWS worktree
  -> terraform init
  -> copy approved terraform/plan.out from the Plan artifact
  -> terraform apply plan.out
```

After apply, a separate read-only smoke project verifies Terraform state:

```text
ci/aws/buildspec.k3s-terraform-smoke.yml
  -> source ci/aws/codebuild-worker-env.sh
  -> render terraform/backend.active.tf
  -> prune disabled Azure provider wiring for the ephemeral AWS worktree
  -> terraform init
  -> terraform output -json
  -> terraform state list
  -> upload terraform/outputs.json and terraform/state.txt
```

Terraform formatting and validation are intentionally handled earlier by GitHub
Actions. The AWS worker should not repeat `terraform fmt -check` or
`terraform validate`; it should spend AWS runtime only on the real backend plan
and approved apply path. The worker also uses `terraform init -reconfigure`
instead of `terraform init -upgrade`, so provider upgrades remain an explicit
repository change.

The prune step edits only the disposable CodeBuild checkout. It exists because
the repository is multi-cloud, but this pipeline is AWS-only. When
`terraform/config/clouds.json` enables only AWS, the worker removes the disabled
Azure provider block and replaces Azure modules with zero-count disabled stubs
before `terraform init`. Without this, the `azurerm` provider can try to
authenticate even though no Azure resources should be planned.

The main `terraform/` root does not create CodeBuild or CodePipeline. It is the
workload infrastructure that the pipeline plans and later should apply.

CodeBuild does not deploy Kubernetes workloads. After Terraform apply, Jenkins
dynamic agents run the EKS Ansible playbooks. A successful Smoke stage means
the Terraform backend is readable and non-empty; it does not mean EKS pods or
CoinOps are healthy.

## Required Local Context

Run local bootstrap from an operator/admin AWS identity. Do not source
`local/generated-env.sh` before creating or updating CI resources.

Verify account and region:

```bash
aws sts get-caller-identity
aws configure get region
echo "$AWS_REGION"
echo "$AWS_DEFAULT_REGION"
```

For this environment, use:

```bash
export AWS_REGION=eu-central-1
export AWS_DEFAULT_REGION=eu-central-1
aws configure set region eu-central-1
```

## GitHub Source

Current test source:

```bash
export COINOPS_CI_GITHUB_REPO=hrenchevskyi-d/coin-ops-aws-code-build
export COINOPS_CI_BRANCH=hrenchevskyi-codebuild
```

The pipeline uses AWS CodeConnections/CodeStar Connections for GitHub access.
If no connection exists yet:

```bash
COINOPS_CI_CREATE_CONNECTION=true \
COINOPS_CI_GITHUB_REPO="$COINOPS_CI_GITHUB_REPO" \
COINOPS_CI_BRANCH="$COINOPS_CI_BRANCH" \
ci/aws/bootstrap-local.sh
```

Then authorize the pending GitHub connection in AWS Console:

```text
AWS Console -> Developer Tools -> Settings -> Connections
```

After authorization, rerun bootstrap with the connection ARN:

```bash
export COINOPS_CI_GITHUB_CONNECTION_ARN='arn:aws:codestar-connections:REGION:ACCOUNT:connection/ID'
```

## Seed Secrets

Fresh AWS accounts need Terraform to seed AWS Secrets Manager once. Regular
CI/CD must not run in seed mode because a partial CodeBuild environment can
overwrite existing secret payloads with empty values.

Default CodeBuild projects are created in read mode:

```bash
TF_VAR_seed_secret_manager=false
```

In read mode, Terraform reads the current AWS Secrets Manager values and uses
them during plan/apply. To perform an intentional one-off seed from CI, set this
only while running `ci/aws/bootstrap-local.sh`:

```bash
export COINOPS_CI_SEED_SECRET_MANAGER=true
```

The local bootstrap writes required seed values to SSM Parameter Store as
`SecureString`, then wires those parameters into CodeBuild as secure env vars
only for that explicit seed mode.

Required local env before bootstrap:

```bash
export TF_VAR_db_password='REPLACE_ME'
export TF_VAR_rabbitmq_password='REPLACE_ME'
export TF_VAR_ghcr_token='REPLACE_ME'
export TF_VAR_cloudflare_api_token='REPLACE_ME'
```

Optional seed values:

```bash
export TF_VAR_tailscale_auth_key='REPLACE_ME'
export TF_VAR_github_oauth_client_id='REPLACE_ME'
export TF_VAR_github_oauth_client_secret='REPLACE_ME'
```

Do not commit these values. After the seed succeeds, rerun bootstrap without
`COINOPS_CI_SEED_SECRET_MANAGER=true` so normal plan/apply returns to read mode.

## Bootstrap Or Update CI

Use this command to create or update the CI control plane:

```bash
COINOPS_CI_GITHUB_REPO="$COINOPS_CI_GITHUB_REPO" \
COINOPS_CI_BRANCH="$COINOPS_CI_BRANCH" \
COINOPS_CI_GITHUB_CONNECTION_ARN="$COINOPS_CI_GITHUB_CONNECTION_ARN" \
ci/aws/bootstrap-local.sh
```

To receive email notifications when the pipeline waits for manual apply
approval, include:

```bash
export COINOPS_CI_APPROVAL_NOTIFICATION_EMAIL='you@example.com'
```

AWS SNS sends a confirmation email. Notifications are delivered only after the
subscription is confirmed.

Use this when Terraform backend bootstrap already exists and only CI resources
need updates:

```bash
COINOPS_CI_GITHUB_REPO="$COINOPS_CI_GITHUB_REPO" \
COINOPS_CI_BRANCH="$COINOPS_CI_BRANCH" \
COINOPS_CI_GITHUB_CONNECTION_ARN="$COINOPS_CI_GITHUB_CONNECTION_ARN" \
ci/aws/bootstrap-local.sh --skip-terraform-bootstrap
```

Expected output includes:

```text
Pipeline:              coin-ops-k3s-deploy
Plan CodeBuild project:coin-ops-k3s-deploy
Apply CodeBuild project:coin-ops-k3s-deploy-apply
Smoke CodeBuild project:coin-ops-k3s-deploy-smoke
Approval SNS topic:    arn:aws:sns:eu-central-1:ACCOUNT:coin-ops-k3s-deploy-approvals
Artifact bucket:       coin-ops-codepipeline-artifacts-ACCOUNT-eu-central-1
Terraform state bucket:coinops-terraform-state-ACCOUNT-eu-central-1
```

The current default pipeline name is `coin-ops-k3s-deploy`. If an older
`coin-ops-k3s-plan` pipeline exists from previous iterations, treat it as a
legacy resource and delete it only after the deploy pipeline is verified.

The default name is also referenced by GitHub repository variables and IAM
policies. Renaming it requires coordinated updates to `bootstrap-local.sh`,
GitHub Actions variables, the GitHub OIDC trigger role policy, dashboards/
operator commands, and this runbook.

## Run Plan And Apply

Start the pipeline:

```bash
aws codepipeline start-pipeline-execution \
  --region eu-central-1 \
  --name coin-ops-k3s-deploy
```

Check pipeline state:

```bash
aws codepipeline get-pipeline-state \
  --region eu-central-1 \
  --name coin-ops-k3s-deploy
```

Check latest CodeBuild build:

```bash
aws codebuild list-builds-for-project \
  --region eu-central-1 \
  --project-name coin-ops-k3s-deploy \
  --sort-order DESCENDING \
  --max-items 1
```

After the Plan stage succeeds, CodePipeline stops at:

```text
ApproveApply -> ApproveTerraformApply
```

Before approving, inspect `terraform/plan.txt` from the Plan artifact or the
Plan CodeBuild logs. Approving this stage allows the separate apply worker to run
`terraform apply` against the exact binary plan artifact from the Plan stage.
Reject the approval if the plan is not expected.

Approve only the newest expected execution. If another pipeline execution or a
local Terraform apply changed the same backend state after this plan was
created, reject the old approval and start a new pipeline execution.

After Apply succeeds, the Smoke stage runs automatically. It reads Terraform
outputs and state from the same backend and fails if the state is empty.

## Read Logs

Get the latest build id:

```bash
BUILD_ID="$(
  aws codebuild list-builds-for-project \
    --region eu-central-1 \
    --project-name coin-ops-k3s-deploy \
    --sort-order DESCENDING \
    --max-items 1 \
    --query 'ids[0]' \
    --output text
)"
echo "$BUILD_ID"
```

Read CloudWatch logs:

```bash
BUILD_UUID="${BUILD_ID#coin-ops-k3s-deploy:}"

aws logs get-log-events \
  --region eu-central-1 \
  --log-group-name /aws/codebuild/coin-ops-k3s-deploy \
  --log-stream-name "terraform-plan/${BUILD_UUID}" \
  --query 'events[].message' \
  --output text
```

The plan also appears in logs because the buildspec runs Terraform through
`tee terraform/plan.txt`.

Read apply logs by switching the project and log group:

```bash
APPLY_BUILD_ID="$(
  aws codebuild list-builds-for-project \
    --region eu-central-1 \
    --project-name coin-ops-k3s-deploy-apply \
    --sort-order DESCENDING \
    --max-items 1 \
    --query 'ids[0]' \
    --output text
)"
APPLY_BUILD_UUID="${APPLY_BUILD_ID#coin-ops-k3s-deploy-apply:}"

aws logs get-log-events \
  --region eu-central-1 \
  --log-group-name /aws/codebuild/coin-ops-k3s-deploy-apply \
  --log-stream-name "terraform-apply/${APPLY_BUILD_UUID}" \
  --query 'events[].message' \
  --output text
```

Read smoke logs by switching the project and log group:

```bash
SMOKE_BUILD_ID="$(
  aws codebuild list-builds-for-project \
    --region eu-central-1 \
    --project-name coin-ops-k3s-deploy-smoke \
    --sort-order DESCENDING \
    --max-items 1 \
    --query 'ids[0]' \
    --output text
)"
SMOKE_BUILD_UUID="${SMOKE_BUILD_ID#coin-ops-k3s-deploy-smoke:}"

aws logs get-log-events \
  --region eu-central-1 \
  --log-group-name /aws/codebuild/coin-ops-k3s-deploy-smoke \
  --log-stream-name "terraform-smoke/${SMOKE_BUILD_UUID}" \
  --query 'events[].message' \
  --output text
```

## Read Plan Artifacts

The pipeline stores artifacts in:

```text
s3://coin-ops-codepipeline-artifacts-ACCOUNT-eu-central-1/
```

List artifacts:

```bash
aws s3 ls \
  s3://coin-ops-codepipeline-artifacts-231648037082-eu-central-1/ \
  --region eu-central-1 \
  --recursive
```

Download and inspect the plan artifact:

```bash
aws s3 cp \
  s3://coin-ops-codepipeline-artifacts-231648037082-eu-central-1/PATH/TO/ARTIFACT \
  /tmp/coinops-plan-artifact.zip \
  --region eu-central-1

rm -rf /tmp/coinops-plan-artifact
unzip /tmp/coinops-plan-artifact.zip -d /tmp/coinops-plan-artifact
less /tmp/coinops-plan-artifact/terraform/plan.txt
```

`terraform/plan.out` is the binary plan. `terraform/plan.txt` is for review.
The smoke artifact contains `terraform/outputs.json` and `terraform/state.txt`.

## Common Failures

Pipeline not found:

```text
PipelineNotFoundException
```

Check region. The pipeline is in `eu-central-1`:

```bash
aws codepipeline list-pipelines --region eu-central-1
```

GitHub source fails:

```text
Connection is pending
```

Authorize the connection in AWS Console, then rerun the pipeline.

Install phase fails on Terraform:

```text
Missing required tool: terraform
```

The worker should install Terraform via `codebuild-worker-env.sh`. Confirm the
pipeline is using the latest pushed branch and buildspec.

Terraform init fails on backend:

```text
use_lockfile is not expected here
```

The worker is using an old Terraform version. Current default is `1.15.2`.

Terraform plan fails reading AWS Secrets Manager:

```text
couldn't find resource coinops-db-secrets|AWSCURRENT
```

Run one explicit seed bootstrap with the required `TF_VAR_*`, repository,
branch, and connection values already exported:

```bash
COINOPS_CI_SEED_SECRET_MANAGER=true \
ci/aws/bootstrap-local.sh --skip-terraform-bootstrap
```

After AWS Secrets Manager contains the expected secret payloads, rerun bootstrap
without `COINOPS_CI_SEED_SECRET_MANAGER=true` to restore the normal read-mode
CodeBuild environment.

Terraform plan fails on Azure CLI:

```text
exec: "az": executable file not found
```

The AWS worker should prune disabled Azure provider wiring before
`terraform init`. Confirm the latest `codebuild-worker-env.sh` is in the source
branch and that `terraform/config/clouds.json` does not include `azure` in
`clouds.enabled`.

Terraform plan fails on Azure client credentials:

```text
AADSTS700038: 00000000-0000-0000-0000-000000000000 is not a valid application identifier
```

This means the pipeline is running an old worker that exported dummy Azure
credentials instead of pruning disabled Azure provider wiring. Confirm the
branch contains the latest `codebuild-worker-env.sh`, then rerun the pipeline.

Terraform apply fails with a stale saved plan:

```text
Error: Saved plan is stale
```

The binary `terraform/plan.out` was created against an older Terraform state
snapshot. Do not retry the same Apply action. Reject or abandon that execution,
make sure no older pending approval is still active, and start a fresh pipeline
execution so Plan runs against the latest state.

## Update Procedure

After changing any file under `ci/aws/`:

```bash
git add ci/aws
git commit -m 'ci: describe change'
git push origin hrenchevskyi-codebuild
git push personal hrenchevskyi-codebuild
```

If `bootstrap-local.sh` changed, rerun bootstrap so AWS resources are updated.

If only a buildspec or `codebuild-worker-env.sh` changed, pushing the branch is
enough for the next pipeline execution.

## Current Limitations

- It does not run Ansible or EKS workload playbooks. Jenkins owns that layer.
- CI secret seed is intentionally opt-in. Normal plan/apply reads cloud secrets
  and refuses to run if `TF_VAR_seed_secret_manager=true` appears without
  `COINOPS_ALLOW_CI_SECRET_SEED=true`.
- The apply worker is separated from the plan worker, but its IAM role is still
  intentionally broad (`PowerUserAccess` plus `IAMFullAccess`) because the
  Terraform root can create networking, compute, load balancing, database,
  secrets, IAM, S3, and CloudWatch resources. Tighten this after the final AWS
  resource set is stable.
- Apply consumes the approved `plan.out`; it does not create a new unapproved
  plan.
