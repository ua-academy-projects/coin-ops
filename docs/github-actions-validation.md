# GitHub Actions Validation

This repository uses GitHub Actions as the first validation gate before AWS
CodeBuild/CodePipeline runs Terraform plans.

The current workflow is `.github/workflows/ci-validation.yml`. It has separate
jobs, so each validation area still runs on its own GitHub-hosted worker:

- `Config validation`
- `Terraform validation`
- `Ansible validation`
- `Validation complete`
- `Trigger AWS CodePipeline`

The trigger job runs only after the relevant validation jobs succeed and the
aggregate `Validation complete` job passes.

## Validation Jobs

### Config validation

Workflow job: `Config validation`

Runs when manual Terraform JSON configs or schemas change:

- `terraform/config/*.json`
- `schemas/terraform-config/**`
- `scripts/validate-json-configs.sh`

It validates the hand-written config files against JSON Schema:

- `clouds.json`
- `general.json`
- `deploy.json`
- `database.json`
- `dns.json`
- `secrets.json`
- `instances.json`
- `networks.json`
- `cloud_mappings.json`
- `observability.json`

After schema validation, the same command runs semantic cross-file checks with
`scripts/validate-terraform-config-semantics.py`. These checks catch references
that are structurally valid JSON but operationally wrong, for example:

- `clouds.control_plane`, `clouds.secret_backend`, and `dns.primary_cloud` must
  be enabled clouds.
- `general.region_profile`, `general.image_profile`, and
  `general.instance_size` must exist in `cloud_mappings.json` for enabled
  clouds.
- Instance subnets, image profiles, and size profiles must exist for the enabled
  clouds where that instance is active.
- Firewall `source_role` and `target_role` values must match roles declared in
  `instances.json`.
- Enabled k3s load balancers must reference existing subnets.

Generated/local files are intentionally excluded:

- `terraform/config/hosts.json`
- `terraform/config/ansible-runtime.json`
- `terraform/local.generated.auto.tfvars.json`
- `ansible/vars/local.generated.json`
- `terraform/sa-key.json`

Run locally:

```bash
make config-validate
```

The schemas also provide editor hover descriptions through `.vscode/settings.json`.

### Terraform validation

Workflow job: `Terraform validation`

Runs when Terraform, AWS CI scripts, or the Makefile change.

Checks:

```bash
terraform fmt -check -recursive
terraform init -backend=false -reconfigure
terraform validate
```

Run locally:

```bash
make terraform-validate
```

The local wrapper temporarily hides ignored `terraform/backend.active.tf` and uses
an isolated `TF_DATA_DIR`, so validation does not depend on local remote-backend
credentials.

Use this to format locally before committing:

```bash
make terraform-fmt
```

### Ansible validation

Workflow job: `Ansible validation`

Runs when Ansible files, Compose templates, or the Makefile change.

The workflow installs Ansible Galaxy collections from `ansible/requirements.yml`
before linting. Without that step, `ansible-lint` cannot load playbooks that use
modules from collections such as `kubernetes.core`, `community.docker`,
`community.general`, or cloud provider collections.

Run locally:

```bash
make ansible-install-requirements
make ansible-lint
```

The initial lint gate uses `.ansible-lint` with `profile: min` and excludes
generated `ansible/artifacts/`. A full strict lint profile currently reports
existing repository debt such as FQCN usage, role variable naming, truthy YAML
values, and idempotency hints. Tighten the profile only after that debt is fixed
or explicitly baselined.

### Validation complete

Workflow job: `Validation complete`

This is an aggregate status job. It checks whether each path-filtered validation
job was required for the current change and whether that required job succeeded.
It also fails if the initial path detection job fails.

Use this as the future required GitHub check for branch protection. Individual
jobs can be skipped when unrelated files change, but `Validation complete`
always runs and gives one stable pass/fail result.

## Full Local Validation

Run the local equivalent of all GitHub Actions validation jobs:

```bash
make ci-validate
```

## Relationship To AWS CodeBuild

GitHub Actions is the fast validation layer. It checks repo structure, config
contracts, Terraform syntax, and Ansible linting.

AWS CodeBuild remains the managed AWS runtime for infrastructure planning and
approved Terraform apply, followed by a read-only smoke check.

On push, GitHub Actions can start the AWS CodePipeline after the validation jobs
finish successfully. This avoids running AWS plans for commits that already fail
repository checks.

The AWS pipeline flow is:

```text
Source -> Plan -> ApproveApply -> Apply -> Smoke
```

The Plan worker does not run `terraform fmt -check` or `terraform validate`.
Those checks belong in GitHub Actions so the expensive AWS runtime starts only
after repository validation has passed.

The trigger is intentionally guarded so the same branch pushed to multiple
repositories does not start duplicate AWS pipeline executions. By default, it
only runs from:

```text
repository: hrenchevskyi-d/coin-ops-aws-code-build
branch:     hrenchevskyi-codebuild
```

Override those defaults with repository variables if needed:

```text
AWS_CODEPIPELINE_TRIGGER_REPOSITORY
AWS_CODEPIPELINE_TRIGGER_BRANCH
```

Required repository variable:

```text
AWS_CODEPIPELINE_TRIGGER_ROLE_ARN
```

Optional repository variables:

```text
AWS_REGION                 default: eu-central-1
AWS_CODEPIPELINE_NAME      default: coin-ops-k3s-deploy
```

Prefer a GitHub OIDC role instead of long-lived AWS access keys. The role only
needs permission to start the deploy pipeline:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "codepipeline:StartPipelineExecution",
      "Resource": "arn:aws:codepipeline:eu-central-1:231648037082:coin-ops-k3s-deploy"
    }
  ]
}
```

Example trust policy for the personal repository and branch:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::231648037082:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
          "token.actions.githubusercontent.com:sub": "repo:hrenchevskyi-d/coin-ops-aws-code-build:ref:refs/heads/hrenchevskyi-codebuild"
        }
      }
    }
  ]
}
```

### Recreate the GitHub OIDC trigger role

This role is independent of CodePipeline's own IAM role and of the Terraform
IAM user. Its only purpose is allowing this exact GitHub repository/branch to
call `StartPipelineExecution` without storing AWS access keys in GitHub.

In AWS IAM:

1. Open **Identity providers** and add an OpenID Connect provider with URL
   `https://token.actions.githubusercontent.com` and audience
   `sts.amazonaws.com`, if it does not already exist.
2. Create a Web identity role using the trust policy above.
3. Attach only the pipeline-start policy above.
4. Copy the role ARN.

The issuer URL returning HTTP 404 in a browser is not an error: it is an OIDC
issuer identifier, not a human-facing site. AWS/GitHub use its discovery and
token endpoints.

Verify the provider and role:

```bash
aws iam list-open-id-connect-providers
aws iam get-role --role-name coin-ops-github-codepipeline-trigger
aws iam list-attached-role-policies --role-name coin-ops-github-codepipeline-trigger
aws iam list-role-policies --role-name coin-ops-github-codepipeline-trigger
```

In the GitHub repository, open **Settings -> Secrets and variables -> Actions ->
Variables** and set:

```text
AWS_CODEPIPELINE_TRIGGER_ROLE_ARN = arn:aws:iam::ACCOUNT:role/ROLE_NAME
AWS_REGION                        = eu-central-1
AWS_CODEPIPELINE_NAME             = coin-ops-k3s-deploy
```

Set the optional repository/branch override variables only if the source moved.
The workflow requests `id-token: write`; without it, GitHub cannot exchange its
OIDC token for temporary AWS credentials.

Push a harmless documentation change or use `workflow_dispatch`, then inspect
the `CI validation` workflow. Manual dispatch validates but does not trigger
CodePipeline; the trigger job intentionally requires a `push` event.

Branch protection is optional for this project. If enabled later, require only
the stable aggregate check `Validation complete`; path-specific jobs may be
legitimately skipped.
