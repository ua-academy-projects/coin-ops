# Coin-Ops AWS Recovery and Operations Runbook

This is the canonical entry point for returning to the project after a full
shutdown. It describes the active AWS deployment. The older VM Compose and
self-managed k3s paths remain in the repository for historical/multicloud use,
but they are not part of the active AWS recovery sequence.

Never commit credentials, `bootstrap.secrets.auto.tfvars`, generated env files,
kubeconfigs, Terraform state, or `terraform/config/ansible-runtime.json`.

## Current Production Model

The checked-in configuration selects:

- AWS as the only enabled cloud, control plane, DNS primary, and secret backend;
- Terraform state in an S3 backend in `eu-central-1`;
- an EKS 1.33 control plane and private managed node group in two AZs;
- public and private EKS API endpoints, with public CIDRs currently unrestricted;
- private worker subnets with outbound access through an AWS NAT Gateway;
- EBS CSI, VPC CNI, CoreDNS, kube-proxy, and CloudWatch Observability add-ons;
- Jenkins installed by Terraform with Helm and configured by JCasC;
- dynamic Jenkins agents running as Kubernetes pods;
- Headlamp and Jenkins behind one Cloudflare Tunnel and Cloudflare Access;
- CoinOps through a public Traefik `LoadBalancer` with fixed EIPs and public A records;
- CNPG PostgreSQL in EKS with S3 backups;
- CloudWatch container logs, dashboard, metrics, alarms, and SNS email alerts.

The high-level control flow is:

```text
Git push
  -> GitHub Actions: JSON schema + semantic checks, Terraform validate, Ansible lint
  -> GitHub OIDC role: start AWS CodePipeline
  -> CodePipeline: Source -> Plan -> manual approval -> Apply -> Smoke
  -> Terraform: AWS network, EKS, IAM, secrets, Cloudflare, Jenkins, observability
  -> Jenkins JCasC jobs: dynamic Kubernetes agent -> Ansible
       -> Headlamp + shared cloudflared connector + log shipping
       -> CNPG + CoinOps services + public ingress
```

## Ownership Boundaries

| Layer | Owns | Does not own |
| --- | --- | --- |
| `terraform/bootstrap-aws.sh` | Terraform IAM user/policy, S3 state bucket, local backend/env files | Workload infrastructure |
| `ci/aws/bootstrap-local.sh` | CodeConnection, artifact bucket, pipeline/build projects, CI IAM/logs/approval topic | EKS workloads |
| GitHub Actions | Fast validation and optional pipeline trigger | Terraform plan/apply |
| CodePipeline/CodeBuild | Remote-state plan, approved apply, state smoke check | Ansible deployment |
| Terraform root | VPC, NAT, EKS, EIPs, IAM, Secrets Manager, Cloudflare, Jenkins, observability | CoinOps/Headlamp Kubernetes manifests |
| Jenkins + Ansible | Headlamp, cloudflared, log shipper, CNPG, CoinOps workloads and ingress | AWS control plane resources |

The S3 state bucket and CI control plane are bootstrap resources, not resources
managed by the main Terraform state. A workload `terraform destroy` does not
necessarily remove them.

## Source of Truth

Review these before every rebuild:

- `terraform/config/clouds.json`: enabled clouds, backend, cloud identities;
- `terraform/config/general.json`: project, region profile, base defaults;
- `terraform/config/networks.json`: VPC, subnets, NAT, legacy k3s LB switches;
- `terraform/config/deploy.json`: EKS, Jenkins, domains, images, app switches;
- `terraform/config/database.json`: managed database switch; currently disabled;
- `terraform/config/dns.json`: Cloudflare account/zone and DNS behavior;
- `terraform/config/secrets.json`: AWS Secrets Manager object names;
- `terraform/config/observability.json`: logs, alarms, dashboard, SNS email;
- `schemas/terraform-config/*.schema.json`: allowed and required JSON fields.

Editor hover help is wired through `.vscode/settings.json`. Generated JSON files
such as `hosts.json` and `ansible-runtime.json` are outputs, not source config.

## Required External Inputs

Infrastructure cannot be reconstructed from Git alone. Obtain or recreate:

1. An AWS admin/operator identity capable of IAM, S3, CodeConnections, and the
   services created by Terraform.
2. Access to the private GitHub repository and permission to authorize the AWS
   GitHub CodeConnection.
3. A GHCR classic PAT or equivalent token that can pull the private images.
4. A Cloudflare API token for the configured account and zone. It must manage
   DNS records, Zero Trust tunnels, Access applications/policies, and identity
   providers.
5. A GitHub OAuth app for Cloudflare Access, including client ID and secret.
6. New database and RabbitMQ passwords. RabbitMQ is retained for rollback mode,
   even though the EKS CoinOps path uses PostgreSQL.
7. An SSH public key at `~/.ssh/ssh-key-coin-ops.pub`. The active EKS path does
   not need VM SSH, but the shared bootstrap still writes this input.
8. Control of `coinops-d.pp.ua` in the configured Cloudflare zone.

Do not reuse expired GHCR, Cloudflare, GitHub OAuth, or AWS credentials from old
generated files.

## Phase 0: Prepare the Workstation

Recommended tools:

- Git and GitHub CLI;
- AWS CLI v2;
- Terraform matching `.github/workflows/ci-validation.yml` (currently 1.15.2);
- Python 3.12 or compatible, `venv`, `pip`, and `make`;
- Ansible, `ansible-lint`, and `check-jsonschema`;
- `kubectl`, Helm, `jq`, `unzip`, and `curl`.

Create the local Python environment and install collections:

```bash
cd /home/notebook/projects/coin-ops
python3 -m venv .venv
. .venv/bin/activate
python -m pip install --upgrade pip
python -m pip install ansible ansible-lint check-jsonschema kubernetes boto3 botocore jmespath passlib
make ansible-install-requirements
```

Validate the repository before touching AWS:

```bash
make ci-validate
git status --short
```

`make ci-validate` runs JSON schema and semantic checks, Terraform format/init/
validate without a backend, and Ansible lint. Fix failures before bootstrapping.

## Phase 1: Confirm AWS and Bootstrap Terraform

Set one region everywhere. Region drift was a previous source of false
`PipelineNotFoundException` failures.

```bash
export AWS_REGION=eu-central-1
export AWS_DEFAULT_REGION=eu-central-1
aws configure set region eu-central-1
aws sts get-caller-identity
aws configure get region
```

Run the account bootstrap with the admin/operator identity, not with stale
credentials from `local/generated-env.sh`:

```bash
cd /home/notebook/projects/coin-ops
bash terraform/bootstrap-aws.sh --activate-backend
```

This creates or updates `bootstrap-terraform-user`, its scoped management
policy, and the versioned/encrypted S3 state bucket. It also writes ignored
local files:

- `local/generated-aws-env.sh` and `local/generated-env.sh`;
- `terraform/backend.active.tf`;
- `terraform/local.generated.auto.tfvars.json`;
- `terraform/bootstrap.secrets.auto.tfvars` if it does not exist;
- `ansible/vars/local.generated.json`.

If AWS reports that the IAM user already has two access keys, delete a known
obsolete key or recover the still-valid generated env. Do not delete an unknown
key without identifying its consumer.

Then switch to the generated Terraform identity and initialize the backend:

```bash
source local/generated-env.sh
aws sts get-caller-identity
make tf-check-backend
terraform -chdir=terraform init -reconfigure
terraform -chdir=terraform state list
```

On a genuinely empty backend, `state list` prints nothing. If it lists old
resources, stop and decide whether this is a recovery of existing state or a
fresh rebuild. Do not apply blindly over unknown state.

## Phase 2: Bootstrap the AWS CI Control Plane

Switch back to the admin/operator identity before this phase. The generated
`bootstrap-terraform-user` manages workload resources but is not the owner of
the CI control-plane bootstrap. For profile-based access, remove environment
credentials first:

```bash
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
export AWS_PROFILE=YOUR_ADMIN_PROFILE
aws sts get-caller-identity
```

Use an equivalent SSO/session method if profiles are not used. Confirm the ARN
before creating IAM roles or CodeConnections.

The source repository and branch currently expected by both Jenkins and CI are:

```bash
export COINOPS_CI_GITHUB_REPO=hrenchevskyi-d/coin-ops-aws-code-build
export COINOPS_CI_BRANCH=hrenchevskyi-codebuild
```

Find an existing connection:

```bash
aws codestar-connections list-connections \
  --region "$AWS_REGION" \
  --provider-type-filter GitHub
```

If none exists, let the bootstrap create a pending one:

```bash
COINOPS_CI_CREATE_CONNECTION=true \
COINOPS_CI_GITHUB_REPO="$COINOPS_CI_GITHUB_REPO" \
COINOPS_CI_BRANCH="$COINOPS_CI_BRANCH" \
ci/aws/bootstrap-local.sh --skip-terraform-bootstrap
```

Authorize it in AWS Console under **Developer Tools -> Settings ->
Connections**, then export the resulting ARN:

```bash
export COINOPS_CI_GITHUB_CONNECTION_ARN='arn:aws:codestar-connections:eu-central-1:ACCOUNT:connection/ID'
```

Create or update the normal read-mode pipeline:

```bash
COINOPS_CI_GITHUB_REPO="$COINOPS_CI_GITHUB_REPO" \
COINOPS_CI_BRANCH="$COINOPS_CI_BRANCH" \
COINOPS_CI_GITHUB_CONNECTION_ARN="$COINOPS_CI_GITHUB_CONNECTION_ARN" \
ci/aws/bootstrap-local.sh --skip-terraform-bootstrap
```

The expected default pipeline is `coin-ops-k3s-deploy`; the historical name
remains even though the active workload is EKS. Verify its control plane:

```bash
aws codepipeline get-pipeline --region "$AWS_REGION" --name coin-ops-k3s-deploy
aws codebuild batch-get-projects --region "$AWS_REGION" --names \
  coin-ops-k3s-deploy \
  coin-ops-k3s-deploy-apply \
  coin-ops-k3s-deploy-smoke
```

See `docs/aws-codebuild-k3s.md` for artifact review, log commands, approval,
GitHub OIDC trigger setup, and pipeline troubleshooting.

## Phase 3: Seed Secrets on a Fresh Rebuild

Skip this phase only when `coinops-db-secrets` and `coinops-app-secrets` already
exist with valid `AWSCURRENT` versions. Inspect metadata, not secret values:

```bash
aws secretsmanager describe-secret --secret-id coinops-db-secrets --region "$AWS_REGION"
aws secretsmanager describe-secret --secret-id coinops-app-secrets --region "$AWS_REGION"
```

For a fresh rebuild, use exactly one intentional seed execution. Export values
in the current shell without writing them to tracked files:

```bash
export TF_VAR_db_password='REPLACE_WITH_NEW_VALUE'
export TF_VAR_rabbitmq_password='REPLACE_WITH_NEW_VALUE'
export TF_VAR_ghcr_token='REPLACE_WITH_PRIVATE_GHCR_READ_TOKEN'
export TF_VAR_cloudflare_api_token='REPLACE_WITH_CLOUDFLARE_TOKEN'
export TF_VAR_github_oauth_client_id='REPLACE_WITH_GITHUB_OAUTH_CLIENT_ID'
export TF_VAR_github_oauth_client_secret='REPLACE_WITH_GITHUB_OAUTH_CLIENT_SECRET'
```

Cloudflare Access is enabled, so the OAuth values are operationally required.
Reconfigure CodeBuild for the one-off seed:

```bash
COINOPS_CI_SEED_SECRET_MANAGER=true \
COINOPS_CI_GITHUB_REPO="$COINOPS_CI_GITHUB_REPO" \
COINOPS_CI_BRANCH="$COINOPS_CI_BRANCH" \
COINOPS_CI_GITHUB_CONNECTION_ARN="$COINOPS_CI_GITHUB_CONNECTION_ARN" \
ci/aws/bootstrap-local.sh --skip-terraform-bootstrap
```

This stores the bootstrap inputs as SSM `SecureString` parameters and injects
them into CodeBuild only for seed mode. It does not make it safe to leave seed
mode enabled: incomplete future inputs could rotate secrets unexpectedly.

## Phase 4: Create the AWS/EKS Infrastructure

Keep an operator identity that can start/read CodePipeline, then start it:

```bash
EXECUTION_ID="$(aws codepipeline start-pipeline-execution \
  --region "$AWS_REGION" \
  --name coin-ops-k3s-deploy \
  --query pipelineExecutionId --output text)"
echo "$EXECUTION_ID"

aws codepipeline get-pipeline-state \
  --region "$AWS_REGION" \
  --name coin-ops-k3s-deploy
```

Wait for Plan, inspect `terraform/plan.txt`, and approve only the newest expected
execution. A fresh EKS deployment can take 30 minutes or more. The node group,
EKS add-ons, EBS volume binding, Jenkins Helm release, and Cloudflare resources
are real readiness dependencies, not just Terraform bookkeeping.

Never approve a plan that unexpectedly deletes/replaces secrets, EIPs, the EKS
cluster, or the Jenkins volume. Never reuse an approval after another apply has
changed state; start a fresh execution to avoid `Saved plan is stale`.

After Apply and Smoke succeed, immediately restore CodeBuild to normal read
mode and clear shell secrets:

```bash
COINOPS_CI_GITHUB_REPO="$COINOPS_CI_GITHUB_REPO" \
COINOPS_CI_BRANCH="$COINOPS_CI_BRANCH" \
COINOPS_CI_GITHUB_CONNECTION_ARN="$COINOPS_CI_GITHUB_CONNECTION_ARN" \
ci/aws/bootstrap-local.sh --skip-terraform-bootstrap

unset TF_VAR_db_password TF_VAR_rabbitmq_password TF_VAR_ghcr_token
unset TF_VAR_cloudflare_api_token TF_VAR_github_oauth_client_id
unset TF_VAR_github_oauth_client_secret
```

When CodeBuild creates EKS, its apply role is the EKS cluster creator and gets
bootstrap cluster-admin. The local Terraform IAM user does not inherit that
Kubernetes authorization. Grant the stable local Terraform identity an EKS
access entry once, using the admin/operator AWS identity:

```bash
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
LOCAL_TERRAFORM_PRINCIPAL="arn:aws:iam::${ACCOUNT_ID}:user/bootstrap-terraform-user"

aws eks describe-access-entry \
  --region "$AWS_REGION" \
  --cluster-name coin-ops-eks \
  --principal-arn "$LOCAL_TERRAFORM_PRINCIPAL" >/dev/null 2>&1 || \
aws eks create-access-entry \
  --region "$AWS_REGION" \
  --cluster-name coin-ops-eks \
  --principal-arn "$LOCAL_TERRAFORM_PRINCIPAL" \
  --type STANDARD

aws eks associate-access-policy \
  --region "$AWS_REGION" \
  --cluster-name coin-ops-eks \
  --principal-arn "$LOCAL_TERRAFORM_PRINCIPAL" \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy \
  --access-scope type=cluster
```

This is currently an explicit bootstrap operation rather than a Terraform
resource. Restrict or remove the access entry when local administration is no
longer needed.

Refresh local generated artifacts if the successful apply ran only in
CodeBuild. A local no-change apply is the simplest supported way to regenerate
the ignored kubeconfig and Terraform-to-Ansible metadata:

```bash
source local/generated-env.sh
aws sts get-caller-identity
make tf-plan
make tf-apply
```

Review the plan first. It should be empty or explain only local/generated
artifacts. Do not apply unexplained cloud changes.

## Phase 5: Bootstrap In-Cluster Automation

Terraform installs Jenkins, but the shared `cloudflared` connector is installed
by the Headlamp Ansible path. This creates a bootstrap dependency: establish
Headlamp/tunnel once from the workstation before relying on public Jenkins.

```bash
source local/generated-env.sh
make eks-kubectl ARGS='get nodes -o wide'
make eks-kubectl ARGS='get pods -A'
make eks-headlamp
```

`make eks-headlamp` installs/reconciles:

- public Traefik ingress with the Terraform-reserved EIPs;
- Headlamp and its administrator service account;
- the shared Cloudflare Tunnel connector serving Headlamp and Jenkins;
- Fluent Bit container log shipping to CloudWatch.

Verify the connector and Headlamp:

```bash
make eks-kubectl ARGS='get pods -n headlamp'
make eks-kubectl ARGS='get pods -n cloudflare-tunnel'
make eks-kubectl ARGS='logs -n cloudflare-tunnel -l app.kubernetes.io/name=cloudflared --tail=100'
```

Jenkins should now be available at `https://jenkins.coinops-d.pp.ua`. Retrieve
the local admin password without printing any other sensitive output:

```bash
terraform -chdir=terraform output -raw jenkins_admin_password
```

If the tunnel is not ready, use a temporary local fallback:

```bash
make eks-kubectl ARGS='-n jenkins port-forward svc/jenkins 8080:8080'
```

Open `http://127.0.0.1:8080` while that command is running.

## Phase 6: Deploy Headlamp and CoinOps Through Jenkins

Terraform JCasC creates two jobs:

- `coinops-eks-deploy-headlamp`;
- `coinops-eks-deploy-coinops`.

Run the Headlamp job once to prove that Jenkins can create a dynamic Kubernetes
agent and reproduce the local bootstrap. Then run the CoinOps job. Keeping the
jobs separate prevents a CoinOps/CNPG failure from redeploying Headlamp.

The CoinOps job installs/reconciles:

- CNPG and the barman-cloud backup plugin;
- PostgreSQL cluster, runtime SQL bootstrap Job, and backup resources;
- proxy, history API, history consumer, and UI workloads;
- Kubernetes secrets, services, network policies, and public ingress.

Watch the jobs from Kubernetes if the Jenkins UI is unavailable:

```bash
make eks-kubectl ARGS='get pods -n jenkins -w'
make eks-kubectl ARGS='logs -n jenkins statefulset/jenkins --tail=200'
```

Dynamic agent pod names start with the Jenkins job name. `Waiting for agent to
connect` normally means the `jnlp` container cannot reach
`jenkins-agent.jenkins.svc.cluster.local:50000`; inspect both containers and the
Jenkins agent Service.

## Phase 7: Acceptance Checklist

### Terraform and AWS

```bash
terraform -chdir=terraform plan -detailed-exitcode
aws eks describe-cluster --region "$AWS_REGION" --name coin-ops-eks \
  --query 'cluster.status' --output text
aws eks describe-nodegroup --region "$AWS_REGION" --cluster-name coin-ops-eks \
  --nodegroup-name system --query 'nodegroup.status' --output text
aws eks list-addons --region "$AWS_REGION" --cluster-name coin-ops-eks
```

Expected: Terraform exit code 0, cluster/node group `ACTIVE`, and all configured
add-ons present.

### Kubernetes

```bash
make eks-kubectl ARGS='get nodes'
make eks-kubectl ARGS='get pods -A'
make eks-kubectl ARGS='get svc -A'
make eks-kubectl ARGS='get ingress -A'
make eks-kubectl ARGS='get cluster -n coinops-data'
make eks-kubectl ARGS='get scheduledbackup -n coinops-data'
make eks-kubectl ARGS='get jobs -n coinops-data'
```

Expected: all nodes `Ready`, no persistent `Pending`, `CrashLoopBackOff`, or
`ImagePullBackOff`, CNPG healthy, runtime bootstrap completed, Traefik has two
external EIPs, and app endpoints exist.

### DNS and HTTP

```bash
dig +short coinops-d.pp.ua A
dig +short www.coinops-d.pp.ua A
dig +short headlamp.coinops-d.pp.ua CNAME
dig +short jenkins.coinops-d.pp.ua CNAME
curl -I https://coinops-d.pp.ua
curl -I https://www.coinops-d.pp.ua
```

Expected: root/`www` are public A records to the reserved ingress EIPs;
Headlamp/Jenkins are proxied tunnel CNAMEs; CoinOps returns a healthy HTTP
response. Cloudflare Access should challenge before Headlamp/Jenkins.

Generate a Headlamp Kubernetes token after passing Cloudflare Access:

```bash
make eks-kubectl ARGS='create token headlamp-admin -n headlamp'
```

### Observability

Confirm the SNS subscription email, then verify:

```bash
aws cloudwatch get-dashboard --region "$AWS_REGION" --dashboard-name coin-ops-observability
aws cloudwatch describe-alarms --region "$AWS_REGION" --alarm-name-prefix coin-ops-
aws logs describe-log-streams \
  --region "$AWS_REGION" \
  --log-group-name /coin-ops/kubernetes/containers \
  --order-by LastEventTime --descending --limit 10
```

Generate a request to CoinOps and confirm recent Traefik/Fluent Bit events before
treating a log-silence alarm as real. Missing data immediately after deployment
can be normal until the first matching event reaches the metric filter.

## Normal Change Workflow

1. Change only canonical config/code; never edit generated runtime files.
2. Run `make ci-validate` locally.
3. Commit and push the configured branch.
4. Wait for the GitHub `Validation complete` check.
5. Review the CodePipeline Terraform plan and approve the newest execution.
6. Run only the affected Jenkins job: Headlamp/platform or CoinOps.
7. Repeat the relevant acceptance checks.

Terraform apply and Jenkins/Ansible deploy are separate reconciliations. A
successful Terraform Smoke stage does not prove CoinOps workloads are healthy.

## Recovery and Troubleshooting

### Pipeline or build not found

Always pass `--region eu-central-1`. Compare `aws configure get region`,
`AWS_REGION`, and `AWS_DEFAULT_REGION`. See `docs/aws-codebuild-k3s.md` for exact
log and artifact commands.

### Terraform cannot read secrets

If Secrets Manager has no `AWSCURRENT` version, use the one-off seed procedure.
Do not make placeholder values the normal CodeBuild environment. If a regular
plan proposes secret replacement, reject it and verify that
`TF_VAR_seed_secret_manager=false` in all three CodeBuild projects.

### EKS node group takes a long time or fails

Twenty to forty minutes can be normal. Inspect health before waiting blindly:

```bash
aws eks describe-nodegroup --region "$AWS_REGION" \
  --cluster-name coin-ops-eks --nodegroup-name system \
  --query 'nodegroup.{status:status,issues:health.issues}'
```

`AsgInstanceLaunchFailures` means EC2 capacity, quota, subnet, or instance-type
eligibility failed. The configured type is `m7i-flex.large`; verify availability
and account restrictions before changing it.

### EKS add-on remains CREATING

```bash
aws eks describe-addon --region "$AWS_REGION" \
  --cluster-name coin-ops-eks --addon-name aws-ebs-csi-driver \
  --query 'addon.{status:status,issues:health.issues}'
```

Check node readiness, the add-on IAM role/OIDC trust, and pods in `kube-system`.
Do not repeatedly apply while the same AWS operation is still converging.

### Jenkins reverse proxy warning

JCasC and `deploy.jenkins.public_url` must both use
`https://jenkins.coinops-d.pp.ua/`. Confirm Cloudflare forwards to
`http://jenkins.jenkins.svc.cluster.local:8080` and that the latest Helm/JCasC
configuration was applied.

### Jenkins agent never connects

Inspect the generated agent pod, `jnlp` logs, `svc/jenkins-agent`, controller
logs, and NetworkPolicy. The explicit tunnel endpoint is
`jenkins-agent.jenkins.svc.cluster.local:50000`.

### Headlamp reports a missing tunnel token

Terraform must run after Cloudflare credentials are valid so
`terraform/config/ansible-runtime.json` and the Jenkins runtime credential
contain `headlamp_tunnel_token`. Never hand-write or commit that generated file.
Regenerate it with a reviewed Terraform apply.

### CoinOps PostgreSQL bootstrap Job does not finish

```bash
make eks-kubectl ARGS='get pods,jobs -n coinops-data'
make eks-kubectl ARGS='logs -n coinops-data job/coinops-postgres-runtime-bootstrap --all-containers'
make eks-kubectl ARGS='describe cluster coinops-postgres -n coinops-data'
```

Common causes are CNPG not ready, GHCR image pull failure, an invalid
PostgreSQL-runtime image/tag, missing database secret, or failed SQL. Fix the
cause and rerun only the CoinOps Jenkins job.

### DNS points to the wrong access path

CoinOps and `www` must be ordinary public A records to the two EKS ingress EIPs.
Headlamp and Jenkins must be proxied CNAMEs to `<tunnel-id>.cfargotunnel.com`.
Reject any plan that turns the public app records into tunnel CNAMEs.

### CloudWatch logs or Traefik metrics have no data

Check `coinops-fluent-bit` in namespace `coinops-cloudwatch`, node IAM
permissions, the configured log group, and recent streams. Traefik metric
filters require structured Traefik access-log fields; generate traffic before
diagnosing a silent dashboard.

## Full Teardown

Use the dedicated helper, not plain `terraform destroy`, because protected
stateful resources, Cloudflare objects, Kubernetes-managed NLBs/target groups,
and EIPs require ordered cleanup:

```bash
source local/generated-env.sh
cd terraform
bash full-destroy.sh --yes-really-destroy-stateful --cloud aws
```

If the secret backend was already removed:

```bash
bash full-destroy.sh --yes-really-destroy-stateful --cloud aws \
  -var='suppress_secret_manager_reads=true'
```

The Terraform bootstrap IAM policy must include CloudWatch Logs tag/list-tag
actions, `iam:ListInstanceProfilesForRole`, and EC2 EIP operations. Rerun
`bootstrap-aws.sh` with an admin identity after policy changes.

After destroy, verify residual billable resources explicitly:

```bash
aws eks list-clusters --region "$AWS_REGION"
aws ec2 describe-nat-gateways --region "$AWS_REGION" \
  --filter Name=state,Values=available,pending
aws elbv2 describe-load-balancers --region "$AWS_REGION"
aws ec2 describe-addresses --region "$AWS_REGION"
aws rds describe-db-instances --region "$AWS_REGION"
aws s3api list-buckets --query 'Buckets[?contains(Name, `coin-ops`)].Name'
```

Also inspect CloudFormation stacks created by EKS add-ons, CloudWatch log groups,
Secrets Manager secrets pending deletion, Cloudflare DNS/Tunnels/Access, the CI
artifact bucket, and the Terraform state bucket. Keep the state bucket and CI
control plane only if a future rebuild is intended.

## Document Map

- `docs/aws-codebuild-k3s.md`: AWS pipeline bootstrap, plan review, logs, artifacts;
- `docs/aws-eks-jenkins.md`: EKS/Jenkins/Ansible design and workload operations;
- `docs/github-actions-validation.md`: validation jobs and GitHub OIDC trigger;
- `terraform/README.md`: Terraform repair and full-destroy mechanics;
- `docs/ansible-config-model.md`: runtime configuration merge model;
- `docs/k3s-cnpg-backups.md`: CNPG backup and restore procedures;
- `docs/k3s-*.md`: legacy self-managed k3s path unless explicitly marked shared.
