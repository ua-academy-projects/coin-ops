# Infrastructure Runbook

This runbook describes the supported lifecycle for the current multi-cloud-ready infrastructure flow.

For exact GCP vs AWS vs Azure support boundaries, see [MULTI_CLOUD_SCOPE.md](/D:/Internship/coin-ops-local/coin-ops/MULTI_CLOUD_SCOPE.md).

The normal operator model is:

- choose the control-plane cloud and secret backend in `terraform/config/clouds.json`
- bootstrap once with the matching script, for example `terraform/bootstrap-gcp.sh`
- source the matching generated env, for example `local/generated-gcp-env.sh`
- seed configured cloud secret managers only when needed
- keep the built-in stateful-resource protections in place for normal work

Current host-role split:

- `jump-host` is bastion-only
- `nat-1` is the dedicated NAT / egress VM for the private subnet
- `app-1` is the public UI node
- `app-2` is the private backend node

## Prerequisites

- Run from WSL/Linux.
- Install Terraform, Ansible, `jq`, Docker-compatible SSH tooling, and the CLI for the chosen control-plane cloud (`gcloud`, `aws`, or `az`).
- Install Ansible collections:

```bash
cd /mnt/d/Internship/coin-ops-local/coin-ops
ansible-galaxy collection install -r ansible/requirements.yml
```

- Authenticate the selected cloud CLI with a human/operator account before bootstrap.

## Generated Local Files

Bootstrap scripts generate local gitignored files:

- `terraform/backend.active.tf`
- `terraform/sa-key.json`
- `terraform/local.generated.auto.tfvars.json`
- `terraform/bootstrap.secrets.auto.tfvars`
- `ansible/vars/local.generated.json`
- `local/generated-gcp-env.sh`, `local/generated-aws-env.sh`, or `local/generated-azure-env.sh`
- `local/generated-env.sh`, an active convenience alias for the last bootstrap script you ran

These files replace the old repo `.env` workflow.

`backend.active.tf` is intentionally generated rather than committed because Terraform backend blocks cannot read JSON locals directly.

Before running Terraform, verify that the generated backend matches
`clouds.control_plane`:

```bash
cd /mnt/d/Internship/coin-ops-local/coin-ops/terraform
bash check-backend.sh
```

If it reports a mismatch, rerun the matching bootstrap and reconfigure Terraform.
For example, to return to the GCP backend:

```bash
bash bootstrap-gcp.sh
terraform init -reconfigure
```

Do not use `-migrate-state` unless the goal is explicitly to copy state between
backends. For normal recovery, use `-reconfigure` so Terraform reconnects to the
already-existing backend selected by `backend.active.tf`.

For broken partial-state recovery, avoid running normal `terraform plan
-refresh-only` against the full current config. Use the repair helper to narrow
the refresh graph and disable secret-version reads:

```bash
cd /mnt/d/Internship/coin-ops-local/coin-ops/terraform
terraform state pull > state-before-repair-$(date +%Y%m%d-%H%M%S).json
bash repair-refresh.sh --enabled gcp plan -var='suppress_secret_manager_reads=true'
bash repair-refresh.sh --enabled gcp apply -var='suppress_secret_manager_reads=true'
```

Use `apply` only after reviewing the `plan` output. The helper runs from a
temporary Terraform copy against the selected backend state; checked-in
Terraform files remain unchanged.

`suppress_secret_manager_reads=true` is the recovery switch for situations
where the configured secret backend was already deleted or is temporarily
unreachable. It prevents Terraform from reading secret **versions** during
plan/refresh/destroy while still allowing the rest of the graph to be
reconciled or torn down.

## Very First Start of Infrastructure

### 1. Review SSOT config

Review the split SSOT files under `terraform/config/` and adjust the committed non-secret defaults if needed:

- `clouds.json`: `clouds.control_plane`, `clouds.enabled`, `clouds.default_instance_clouds`, `clouds.providers`, and `clouds.backends`
- `general.json`: project/user/SSH/region/image defaults
- `deploy.json`: domain, TLS/certbot policy, runtime backend, image defaults, ports, and Ansible provisioning defaults
- `database.json`: managed PostgreSQL defaults plus GCP/AWS/Azure sizing profiles
- `dns.json`: `dns.primary_cloud` and Cloudflare defaults
- `secrets.json`: logical secret names used by all cloud secret managers
- `instances.json`: VM topology, per-VM cloud overrides, and explicit `gateway` hosts
- `networks.json`: per-cloud CIDR/subnet layout, firewall rules, Tailscale settings, remote route metadata, and optional workload static-route fallback roles

For the current architecture, keep `tailscale.snat_subnet_routes = true`
unless the gateway design is changed to something stronger than a single-NIC
external-subnet router. Disabling SNAT breaks return-path routing for private
workload hosts behind that gateway.

Remote cloud CIDRs should normally be delivered through cloud-native route
tables. Leave `tailscale.static_route_roles` empty unless you are explicitly
debugging with host-level fallback routes.

### Multicloud acceptance

After `terraform apply`, `ansible/provision.yml`, and `ansible/deploy.yml`,
check the routing path in this order:

```bash
ssh -F /home/notebook/projects/coin-ops/terraform/config/ssh_config coinops-gcp-gateway 'sudo tailscale status'
ssh -F /home/notebook/projects/coin-ops/terraform/config/ssh_config coinops-gcp-gateway 'sudo iptables -t nat -S POSTROUTING | grep tailscale0'
ssh -F /home/notebook/projects/coin-ops/terraform/config/ssh_config coinops-aws-app-2 'curl -vk https://localhost:8443/health'
ssh -F /home/notebook/projects/coin-ops/terraform/config/ssh_config coinops-gcp-app-1 'curl -vk --connect-timeout 5 https://10.30.1.95:8443/health'
```

The second command should show a rule like:

```bash
-A POSTROUTING -s 10.20.0.0/16 -o tailscale0 -j MASQUERADE
```

If the backend is healthy locally on `app-2` but the final cross-cloud curl
fails, check for stale fallback routes on workload hosts:

```bash
ssh -F /home/notebook/projects/coin-ops/terraform/config/ssh_config coinops-gcp-app-1 'ip route'
ssh -F /home/notebook/projects/coin-ops/terraform/config/ssh_config coinops-aws-app-2 'ip route'
```

`app-ui` and `app-backend` should not keep `via ... onlink` routes for remote
cloud CIDRs unless `tailscale.static_route_roles` was intentionally enabled for
debugging.

### 2. Run bootstrap

```bash
cd /mnt/d/Internship/coin-ops-local/coin-ops/terraform
bash bootstrap-gcp.sh
```

For AWS as the selected control-plane, run:

```bash
cd /mnt/d/Internship/coin-ops-local/coin-ops/terraform
bash bootstrap-aws.sh
```

For Azure as the selected control-plane, run:

```bash
cd /mnt/d/Internship/coin-ops-local/coin-ops/terraform
bash bootstrap-azure.sh
```

Bootstrap chooses only the Terraform backend/operator environment. It does not change DNS ownership. DNS is controlled separately by `terraform/config/dns.json` through `dns.primary_cloud`.

### 3. Fill the bootstrap secrets file

Edit `terraform/bootstrap.secrets.auto.tfvars` and replace the placeholder values:

- `db_password`
- `rabbitmq_password`
- `ghcr_token`
- `cloudflare_api_token`

### 4. Load the generated environment

```bash
cd /mnt/d/Internship/coin-ops-local/coin-ops
source local/generated-gcp-env.sh
```

Use the cloud-matching generated file for AWS or Azure.

### 5. Seed secret managers and create infrastructure

```bash
cd /mnt/d/Internship/coin-ops-local/coin-ops/terraform
terraform init
terraform apply -var='seed_secret_manager=true'
```

This first apply:

- creates or updates secret manager records in every enabled cloud
- creates the infrastructure
- creates managed PostgreSQL in every enabled cloud when `database.enabled=true`
- uses the explicit backend from `terraform/backend.active.tf`
- generates `terraform/config/ssh_config`
- generates `terraform/config/ansible-runtime.json`

For an Azure-only end-to-end deploy where secrets live in Azure:

1. Set `clouds.control_plane = "azure"`, `clouds.secret_backend = "azure"`, and `clouds.enabled = ["azure"]` in `terraform/config/clouds.json`.
2. Run `terraform/bootstrap-azure.sh`.
3. Source `local/generated-azure-env.sh`.
4. Fill `terraform/bootstrap.secrets.auto.tfvars`.
5. Run `terraform init -reconfigure`.
6. Run `terraform apply -var='seed_secret_manager=true'`.
7. Run provision and deploy.

### 6. Provision and deploy

```bash
cd /mnt/d/Internship/coin-ops-local/coin-ops
ansible-playbook -i ansible/inventory ansible/provision.yml
ansible-playbook -i ansible/inventory ansible/deploy.yml
```

### 7. Smoke-check the result

```bash
ansible-inventory -i ansible/inventory --graph
APP_DOMAIN="$(jq -r '.deploy.app_domain' terraform/config/deploy.json)"
curl -I https://"$APP_DOMAIN"
curl https://"$APP_DOMAIN"/health
```

Notes:

- External port `80` is intentionally closed.
- Cloudflare proxy is the intended public entry point.
- `dns.primary_cloud` owns `APP_DOMAIN`; other simultaneous cloud deployments are not assigned DNS names and should be checked by direct public IP.
- `clouds.secret_backend` controls which cloud Ansible reads secrets from during deploy.
- Sourcing `local/generated-gcp-env.sh` or `local/generated-aws-env.sh` also sets
  `COINOPS_SECRET_BACKEND` as an operator override. This lets AWS-only deploys
  read AWS Secrets Manager even if the committed default still says `gcp`.

## Validation Path For Infrastructure Refactors

Run these before applying refactored infrastructure changes to a real project:

```bash
cd /mnt/d/Internship/coin-ops-local/coin-ops
git diff --check
```

Validate Terraform structure without touching the remote backend:

```bash
cd terraform
terraform fmt -check -recursive
terraform init -backend=false
terraform validate
```

Validate the active backend artifact after bootstrap:

```bash
bash bootstrap-gcp.sh
grep -n 'backend "gcs"' backend.active.tf

bash bootstrap-aws.sh
grep -n 'backend "s3"' backend.active.tf
grep -n 'use_lockfile = true' backend.active.tf

bash bootstrap-azure.sh
grep -n 'backend "azurerm"' backend.active.tf
```

Validate planning scenarios by changing only split JSON files under `terraform/config/`:

- `clouds.enabled = ["gcp"]`
- `clouds.enabled = ["aws"]`
- `clouds.enabled = ["azure"]`
- `clouds.enabled = ["gcp", "aws"]`
- `clouds.enabled = ["gcp", "azure"]`
- `clouds.enabled = ["aws", "azure"]`
- `clouds.enabled = ["gcp", "aws", "azure"]`
- `instances.<name>.clouds` set for one mixed-placement VM
- `clouds.secret_backend = "gcp"`
- `clouds.secret_backend = "aws"`
- `clouds.secret_backend = "azure"`
- `dns.primary_cloud` switched between available clouds

For each scenario:

```bash
terraform plan -out=tfplan
terraform show -no-color tfplan > tfplan.txt
```

Check that:

- only the selected cloud modules receive VMs
- root/`www` DNS records point to `dns.primary_cloud`
- no DNS records are created for non-primary clouds
- `public_endpoints` contains `direct_url` for every public UI cloud
- `database_endpoints` contains managed PostgreSQL metadata for every enabled cloud
- `terraform/config/ansible-runtime.json` contains `database.host`, `database.port`, `database.name`, `database.user`, and `database.managed` for every enabled cloud

Validate Ansible after Terraform has produced inventory artifacts:

```bash
cd ..
ansible-inventory -i ansible/inventory --graph
ansible-playbook -i ansible/inventory ansible/provision.yml --syntax-check
ansible-playbook -i ansible/inventory ansible/deploy.yml --syntax-check
```

The inventory graph should contain cloud groups and role groups such as `gcp`, `aws`, `azure`, `role_app_ui`, `role_app_backend`, `role_jump_host`, `role_gateway`, and `role_nat`.

## Correctly Destroy Infrastructure Without Affecting Important Parts

Important non-compute infrastructure is protected with Terraform hard guards:

- Cloud SQL / RDS / Azure Database for PostgreSQL resources
- Secret Manager / Secrets Manager / Key Vault secret containers

To remove only compute and compute-adjacent runtime artifacts, use targeted destroy:

```bash
cd /mnt/d/Internship/coin-ops-local/coin-ops
source local/generated-gcp-env.sh
cd terraform
terraform destroy \
  -target=module.gcp_nat_route \
  -target=module.gcp_instances \
  -target=module.aws_nat_route \
  -target=module.aws_instances \
  -target=module.azure_nat_route \
  -target=module.azure_instances \
  -target=local_file.hosts \
  -target=local_file.ssh_config \
  -target=local_file.ansible_runtime \
  -target=null_resource.sync_ssh_config
```

The equivalent Make target is:

```bash
make tf-destroy-compute TF_DESTROY_ARGS='-auto-approve'
```

## Full Destroy of Infrastructure

Use this only when you intentionally want to remove everything, including stateful resources.

```bash
cd /mnt/d/Internship/coin-ops-local/coin-ops
source local/generated-gcp-env.sh
cd terraform
bash full-destroy.sh --yes-really-destroy-stateful
```

This helper creates a temporary Terraform copy, removes GCP/AWS/Azure hard destroy protections there, and runs `terraform destroy` against the same backend state. The checked-in Terraform files remain unchanged. Disabled clouds are stubbed inside the temporary copy, so an AWS/GCP-only destroy does not configure the Azure provider.

When recovering from a broken destroy or from already-deleted secret versions,
pass the recovery switch through to the helper:

```bash
cd /mnt/d/Internship/coin-ops-local/coin-ops
source local/generated-gcp-env.sh
cd terraform
bash full-destroy.sh --yes-really-destroy-stateful --cloud gcp -var='suppress_secret_manager_reads=true'
```

`full-destroy.sh` now also performs provider-side pre-cleanup for stateful
resources before the final Terraform destroy:

- disables AWS RDS deletion protection
- disables and deletes GCP Cloud SQL instances found in state
- deletes GCP private service connections
- deletes GCP reserved private-service-access peering ranges

Use plain `terraform destroy` only for compute-only teardown or normal
day-to-day iteration. Use `full-destroy.sh` for intentional stateful teardown.

To fully destroy only one cloud without touching the others, pass `--cloud`.
For example, to remove only Azure-managed infrastructure, including protected
database and secret resources:

```bash
cd /mnt/d/Internship/coin-ops-local/coin-ops
source local/generated-gcp-env.sh
cd terraform
bash full-destroy.sh --yes-really-destroy-stateful --cloud azure
```

Supported values are `all`, `gcp`, `aws`, and `azure`. Single-cloud mode uses
targeted module destroys inside the temporary copy instead of removing other
clouds from `clouds.enabled`.

If a full destroy is interrupted and the next Terraform run fails to acquire the
S3 native lock, first verify that no Terraform process is still running. Then
remove only the stale `.tflock` object for the active backend:

```bash
aws s3 ls s3://coinops-terraform-state-231648037082-eu-central-1/infra/state/ --region eu-central-1
aws s3 rm s3://coinops-terraform-state-231648037082-eu-central-1/infra/state/terraform.tfstate.tflock --region eu-central-1
```

Do not remove `terraform.tfstate` or any state version objects. Remove only the
`.tflock` object after confirming the previous Terraform command was stopped.

## Secret Rotation

To rotate bootstrap-managed secrets:

1. Edit `terraform/bootstrap.secrets.auto.tfvars`
2. Run:

```bash
cd /mnt/d/Internship/coin-ops-local/coin-ops/terraform
terraform apply -var='seed_secret_manager=true'
```

3. Re-run deploy:

```bash
cd ..
ansible-playbook -i ansible/inventory ansible/deploy.yml
```
