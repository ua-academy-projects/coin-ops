# AWS EKS, Jenkins, and Ansible Runbook

This document explains the active Kubernetes automation layer. Start with
`runbook.md` when recovering the entire environment from zero.

## Layering

Terraform and Ansible intentionally own different resource types:

```text
Terraform
  VPC/subnets/routes/NAT/EIPs
  EKS control plane/private managed node group/add-ons/IAM
  AWS Secrets Manager and CNPG backup IAM/S3
  Cloudflare tunnel configuration, Access, and DNS
  Jenkins Helm release, volume, RBAC, JCasC, credentials, jobs
  CloudWatch log group/dashboard/alarms/SNS

Jenkins dynamic agent -> Ansible
  public Traefik ingress
  Headlamp and shared cloudflared connector
  Fluent Bit log shipping
  CNPG operator/plugin/PostgreSQL/runtime SQL/backups
  CoinOps proxy/API/consumer/UI/services/ingress/network policies
```

Terraform does not execute the application Ansible playbooks. CodePipeline
Smoke verifies Terraform state only. Kubernetes health is a separate acceptance
gate.

## EKS Network Model

- EKS control plane uses both public and private endpoints.
- Managed nodes run only in `internal` and `private-b` subnets.
- `external` and `public-b` are public subnets used by NAT/public ingress.
- Private nodes reach ECR/GHCR, package repositories, and AWS APIs through the
  managed NAT Gateway.
- Traefik creates a Kubernetes-managed public NLB and attaches Terraform-reserved
  EIPs through service annotations.
- CoinOps and `www` use public A records to those EIPs.
- Headlamp and Jenkins remain ClusterIP services and use one outbound
  `cloudflared` connector. They do not need a public load balancer or bastion.

The active path does not require a jump host. A jump host and VM k3s instances
are legacy resources and are gated off by the current EKS configuration.

## Terraform-Created Kubernetes Resources

`terraform/eks_jenkins.tf` installs Jenkins with the official Helm chart. The
chart values come from `terraform/helm/jenkins/values.yaml.tftpl`; JCasC comes
from `terraform/helm/jenkins/casc.yaml.tftpl`.

JCasC defines:

- local `admin` authentication and no anonymous access;
- English locale and dark theme;
- Kubernetes cloud `eks` for ephemeral agents;
- internal controller and agent endpoints;
- GitHub, GHCR, DB, Cloudflare, CNPG backup, and runtime-metadata credentials;
- `coinops-eks-deploy-headlamp` and `coinops-eks-deploy-coinops` jobs.

Terraform also grants the Jenkins service account `cluster-admin`. This is
pragmatic for the internship project but broad for production. Treat Jenkins
admin access and its service-account token as full cluster-admin access.

Retrieve access data:

```bash
terraform -chdir=terraform output -raw jenkins_public_url
terraform -chdir=terraform output -raw jenkins_admin_password
```

The password is a sensitive Terraform-state value. Do not paste it into tickets,
logs, shell history shared with others, or committed files.

## Bootstrap Dependency

The Cloudflare tunnel object/config/DNS is created by Terraform, but the
in-cluster cloudflared Deployment is created by the Headlamp Ansible role.
Therefore the first deployment must be one of:

1. Run `make eks-headlamp` locally with the generated EKS kubeconfig; or
2. Port-forward Jenkins locally, log in, and run the Headlamp job.

The supported recovery runbook uses option 1:

```bash
source local/generated-env.sh
make eks-kubectl ARGS='get nodes'
make eks-headlamp
```

After cloudflared is healthy, both public routes work:

```text
https://headlamp.coinops-d.pp.ua -> Headlamp ClusterIP
https://jenkins.coinops-d.pp.ua  -> Jenkins ClusterIP
```

Cloudflare Access is the outer identity gate. Jenkins local login and Headlamp
Kubernetes token authentication still apply behind it.

## Jenkins Jobs

Both Jenkinsfiles use a dynamic Kubernetes pod with:

- a Python 3.12 `tools` container;
- a Jenkins inbound `jnlp` agent container;
- the Jenkins service account;
- an in-cluster kubeconfig generated from the pod service-account token;
- a temporary Python virtualenv and Ansible Galaxy collections;
- credentials injected only around the stage that consumes them.

The agent is disposable. Do not expect files from a completed workspace to be
available to another build.

### Headlamp job

Source: `ci/jenkins/Jenkinsfile.eks-headlamp`

Runs `make eks-headlamp`, which reconciles public Traefik, Headlamp, cloudflared,
and Fluent Bit. Run it after Terraform changes EIPs, the tunnel token, domains,
Headlamp settings, log shipping, or relevant Ansible roles.

### CoinOps job

Source: `ci/jenkins/Jenkinsfile.eks-coinops`

Runs `make eks-coinops`, which validates runtime inputs and then reconciles
CNPG, PostgreSQL bootstrap SQL, backup resources, CoinOps workloads, and public
ingress. Run it after image/config/SQL/CNPG/application-role changes.

The jobs use `disableConcurrentBuilds()`. Do not deploy the same layer manually
while its Jenkins job is active.

## Manual Reconciliation

Jenkins is preferred after bootstrap, but the Make targets are valid operator
fallbacks:

```bash
source local/generated-env.sh
make eks-headlamp
make eks-coinops
```

Both use `ansible/artifacts/kubeconfig-aws-eks.yaml`, generated by Terraform.
If the file is missing after a remote CodeBuild apply, perform a reviewed local
no-change apply to regenerate local artifacts. When CodeBuild created the
cluster, first grant `bootstrap-terraform-user` an EKS access entry as documented
in `runbook.md`; EKS cluster-creator permissions are not inherited by other IAM
identities.

`make eks-platform` currently imports only `eks-headlamp.yml`; it is not a full
CoinOps deployment. Run `make eks-coinops` separately.

## Verification

Controller and agents:

```bash
make eks-kubectl ARGS='get statefulset,pods,svc,pvc -n jenkins'
make eks-kubectl ARGS='logs -n jenkins statefulset/jenkins --tail=200'
```

Headlamp and tunnel:

```bash
make eks-kubectl ARGS='get all -n headlamp'
make eks-kubectl ARGS='get pods -n cloudflare-tunnel'
make eks-kubectl ARGS='create token headlamp-admin -n headlamp'
```

CoinOps and data:

```bash
make eks-kubectl ARGS='get pods,svc,ingress -A'
make eks-kubectl ARGS='get cluster,scheduledbackup,job -n coinops-data'
make eks-kubectl ARGS='describe cluster coinops-postgres -n coinops-data'
```

Do not use `make headlamp-token` for EKS: that target belongs to the tunneled
self-managed k3s kubeconfig. Use `make eks-kubectl` as shown above.

## Troubleshooting

### Jenkins is not publicly reachable

Port-forward the controller:

```bash
make eks-kubectl ARGS='-n jenkins port-forward svc/jenkins 8080:8080'
```

Then inspect cloudflared. The tunnel configuration must contain both hostnames,
and the pod must have the token generated by the latest Terraform state.

### Reverse proxy warning

Keep these consistent:

- `deploy.jenkins.public_url` in `terraform/config/deploy.json`;
- JCasC `unclassified.location.url`;
- Cloudflare hostname;
- the trailing slash expected by Jenkins.

The current value is `https://jenkins.coinops-d.pp.ua/`.

### Agent waits forever to connect

```bash
make eks-kubectl ARGS='get pods -n jenkins -o wide'
make eks-kubectl ARGS='get svc,endpoints -n jenkins'
make eks-kubectl ARGS='logs -n jenkins POD_NAME -c jnlp'
make eks-kubectl ARGS='logs -n jenkins statefulset/jenkins --tail=300'
```

The required endpoint is
`jenkins-agent.jenkins.svc.cluster.local:50000`. Confirm the `jenkins-agent`
Service has endpoints and that controller JCasC still sets `slaveAgentPort`.

### Workspace references a workstation Python path

Jenkins must use the `.venv` created inside its own workspace. The Makefile
selects the repo virtualenv only for localhost execution. Confirm the job runs
from the current branch and has not inherited a generated local override.

### Generated kubeconfig is missing

Local Ansible requires `ansible/artifacts/kubeconfig-aws-eks.yaml`. Jenkins
generates its own in-cluster kubeconfig and rewrites the runtime metadata path in
its disposable checkout. Do not copy a workstation kubeconfig into Jenkins.

### Headlamp tunnel token is empty

The token is a Terraform-derived value. Re-run a reviewed Terraform apply with
valid Cloudflare credentials, then reconcile Jenkins Helm/JCasC and rerun the
Headlamp job. Never put the token in `deploy.json`.

### CoinOps bootstrap Job remains active

Inspect the actual pod logs instead of increasing Ansible retries:

```bash
make eks-kubectl ARGS='get pods -n coinops-data -l job-name=coinops-postgres-runtime-bootstrap'
make eks-kubectl ARGS='logs -n coinops-data job/coinops-postgres-runtime-bootstrap --all-containers'
make eks-kubectl ARGS='get events -n coinops-data --sort-by=.lastTimestamp'
```

The Job waits for CNPG PostgreSQL, then applies `deploy/sql/runtime/*.sql`. Check
CNPG readiness, GHCR pulls, mounted SQL, and credentials before rerunning.

### Old Jenkins version or configuration persists

Changing `controller_tag`, plugins, JCasC, or chart values requires Terraform to
update the Helm release. Confirm the plan contains `helm_release.jenkins`, wait
for controller rollout, and verify the StatefulSet image. Jenkins persistent
storage preserves jobs/state, while JCasC reasserts managed configuration.

## Known Constraints

- `cluster-admin` for Jenkins is intentionally overprivileged.
- Plugins and chart version are not fully pinned when `chart_version` is empty.
- Agent images install tools at runtime, so jobs depend on Debian, PyPI, GitHub,
  and Kubernetes download availability through NAT.
- EKS public API access currently allows `0.0.0.0/0`; authentication still
  applies, but production should restrict CIDRs.
- The local Terraform user's EKS access entry is a documented bootstrap action,
  not currently managed in Terraform.
- `homepage.enabled` and its DNS data remain in shared config, but the active
  EKS platform playbook does not deploy Homepage. It is not an acceptance
  requirement for CoinOps/Headlamp.
