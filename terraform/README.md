# Terraform Operations

This directory contains the multicloud infrastructure root module plus helper
scripts for bootstrapping, repair, and teardown.

## Normal Lifecycle

For the active environment, GitHub Actions validates changes and CodePipeline
runs the reviewed plan/apply lifecycle. Use the following only for deliberate
local operation or recovery after completing `runbook.md` bootstrap:

```bash
cd terraform
terraform init -reconfigure
terraform plan
terraform apply
```

When Azure is the control plane, remember that the backend Storage account name
must be globally unique across Azure. `bootstrap-azure.sh` now checks this and
fails early with a clear message if the configured name is already taken
outside the expected resource group. It also validates Azure naming rules:
3-24 characters, lowercase letters and numbers only.

When the secret backend has already been torn down or you are repairing drift,
disable secret-version reads during planning:

```bash
terraform plan -var='suppress_secret_manager_reads=true'
```

The same switch is safe for `apply`, `destroy`, and `refresh-only`.

Use `suppress_secret_manager_reads=true` only as a recovery / teardown switch.
It tells Terraform not to read secret **versions** from the configured cloud
secret backend while it reconciles the rest of the graph. This is useful when
the secret container still exists in configuration but the underlying secret
versions were already deleted, or when the secret backend is being
removed as part of the current teardown.

## Current Active Topology

The current checked-in deployment is AWS-only and uses managed EKS. Terraform
creates:

- a VPC with two private EKS subnets and two public subnets across two AZs;
- an AWS NAT Gateway for private-node egress;
- an EKS control plane, private managed node group, and managed add-ons;
- fixed EIPs consumed by the Kubernetes public Traefik Service;
- AWS Secrets Manager objects and CNPG S3 backup identity/bucket;
- Cloudflare DNS, Tunnel, Access, and GitHub identity provider;
- Jenkins through Helm/JCasC, with dynamic Kubernetes agents;
- CloudWatch logs, Container Insights, alarms, dashboard, and SNS alerts.

The current AWS path does not use a jump host, EC2 k3s servers, VM NAT routing,
or Tailscale. Those shared modules remain for legacy/multicloud configurations.
Private EKS nodes use the managed NAT Gateway for outbound access.

## Post-Deploy Acceptance

After Terraform apply:

```bash
terraform output aws_eks_cluster_name
terraform output aws_eks_kubeconfig_file
terraform output jenkins_public_url
cd ..
make eks-kubectl ARGS='get nodes'
make eks-kubectl ARGS='get pods -A'
```

Then bootstrap/reconcile Headlamp and the shared tunnel before relying on public
Jenkins:

```bash
make eks-headlamp
```

Deploy CoinOps through Jenkins or `make eks-coinops`, then complete the
acceptance checklist in `runbook.md`.

## Troubleshooting

If EKS nodes do not join:

- inspect `aws eks describe-nodegroup ... --query 'nodegroup.health.issues'`;
- verify private subnet routes point to the NAT Gateway;
- verify the configured instance type is available and permitted;
- inspect EKS node-role policy attachments and security groups.

If Headlamp/Jenkins tunnel apply fails with Cloudflare authentication errors:
- verify `dns.cloudflare.account_id` matches the Cloudflare account that owns
  Zero Trust
- verify the Cloudflare API token has Zero Trust Tunnel, Access Apps/Policies,
  Access Identity Providers, and DNS permissions

For complete EKS/Jenkins troubleshooting, use `docs/aws-eks-jenkins.md`.

## Repairing Drift

If resources were partially deleted outside Terraform, prefer the repair helper
instead of immediately hand-editing state:

```bash
cd terraform
bash repair-refresh.sh --enabled aws apply -var='suppress_secret_manager_reads=true'
```

Use `plan` instead of `apply` first if you want to inspect the refresh-only
delta before it is written back to state.

## Full Stateful Teardown

Stateful resources in this repository have `prevent_destroy` and
provider-side deletion protection enabled. To tear everything down on purpose,
use the dedicated helper:

```bash
cd terraform
bash full-destroy.sh --yes-really-destroy-stateful --cloud all
```

Single-cloud teardown is also supported:

```bash
bash full-destroy.sh --yes-really-destroy-stateful --cloud gcp
bash full-destroy.sh --yes-really-destroy-stateful --cloud aws
bash full-destroy.sh --yes-really-destroy-stateful --cloud azure
```

You can pass additional Terraform arguments through to the final destroy
command. The most useful one during recovery is:

```bash
bash full-destroy.sh --yes-really-destroy-stateful --cloud aws -var='suppress_secret_manager_reads=true'
```

`full-destroy.sh` works from an isolated temporary copy of the Terraform root
and keeps the checked-in files untouched. In that temporary copy it:

- removes `prevent_destroy` from database, secrets, and CNPG backup resources
- sets CNPG object-storage backup buckets to force-delete only in the temporary copy
- keeps CNPG backup resources instantiated in the temporary copy so destroy
  receives the force-delete bucket configuration
- deletes Kubernetes-managed EKS load balancers and target groups before
  Terraform releases their fixed EIPs and public subnets
- waits for EIP disassociation before the main AWS destroy
- includes AWS observability resources in AWS-only targeted teardown:
  CloudWatch alarms, dashboard, log metric filters, log group, SNS alerts,
  the CloudWatch Agent SSM parameter, and the EC2 observability IAM profile
- disables AWS RDS deletion protection before teardown
- disables and deletes GCP Cloud SQL instances found in state before teardown
- deletes GCP private service connections and reserved peering ranges that can
  otherwise outlive Cloud SQL and block VPC deletion
- retries GCP private service connection deletion while Google is still
  releasing producer services such as Cloud SQL from Service Networking
- treats the connection as already gone if Service Networking stops listing it
  even while delete calls still return stale cleanup errors
- falls back immediately to deleting or request-deleting any remaining Compute
  Engine peerings on the target VPC when Service Networking reports that a
  producer service is still blocking connection deletion
- then runs `terraform destroy` against the same backend state

If the secret backend or its versions were already removed, pass the recovery
switch through to the helper:

```bash
bash full-destroy.sh --yes-really-destroy-stateful --cloud aws -var='suppress_secret_manager_reads=true'
```

## Manual State Surgery

Use `terraform state rm ...` only after confirming the real cloud resource is
already gone. In most cases `repair-refresh.sh` or `full-destroy.sh` should be
enough, and state removal should be a last resort rather than the default flow.
