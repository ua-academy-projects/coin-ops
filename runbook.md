# Infrastructure Runbook

This runbook describes the supported lifecycle for the current multi-cloud-ready infrastructure flow.

For exact GCP vs AWS support boundaries, see [MULTI_CLOUD_SCOPE.md](/D:/Internship/coin-ops-local/coin-ops/MULTI_CLOUD_SCOPE.md).

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
- Install Terraform, Ansible, `jq`, Docker-compatible SSH tooling, and the CLI for the chosen control-plane cloud (`gcloud` or `aws` today).
- Install Ansible collections:

```bash
cd /mnt/d/Internship/coin-ops-local/coin-ops
ansible-galaxy collection install -r ansible/requirements.yml
```

- Authenticate the selected cloud CLI with a human/operator account before bootstrap. For the default GCP path:

```bash
gcloud auth login
gcloud auth list
```

Do not run bootstrap while the active `gcloud` account is the Terraform service account.

## Generated Local Files

Bootstrap scripts generate local gitignored files:

- `terraform/backend.active.tf`
- `terraform/sa-key.json`
- `terraform/local.generated.auto.tfvars.json`
- `terraform/bootstrap.secrets.auto.tfvars`
- `ansible/vars/local.generated.json`
- `local/generated-gcp-env.sh` or `local/generated-aws-env.sh`
- `local/generated-env.sh`, an active convenience alias for the last bootstrap script you ran

These files replace the old repo `.env` workflow.

`backend.active.tf` is intentionally generated rather than committed because Terraform backend blocks cannot read JSON locals directly.

Generated env files contain only local credentials and operator paths. Committed non-secret deploy settings such as domain, TLS mode, ports, and image tags stay in the split JSON files under `terraform/config/`.

## Very First Start of Infrastructure

### 1. Review SSOT config

Review the split SSOT files under `terraform/config/` and adjust the committed non-secret defaults if needed:

- `clouds.json`: `clouds.control_plane`, `clouds.enabled`, `clouds.default_instance_clouds`, `clouds.providers`, and `clouds.backends`
- `general.json`: project/user/SSH/region/image defaults
- `deploy.json`: domain, TLS/certbot policy, runtime backend, image defaults, ports, and Ansible provisioning defaults
- `database.json`: managed PostgreSQL defaults plus GCP/AWS sizing profiles
- `dns.json`: `dns.primary_cloud` and Cloudflare defaults
- `secrets.json`: logical secret names used by all cloud secret managers
- `instances.json`: VM topology and per-VM cloud overrides

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

AWS bootstrap creates an S3 state bucket and uses Terraform's native S3 lockfile
support in the generated backend artifact. It also grants the bootstrap identity
permissions for EC2/VPC, RDS, and Secrets Manager so AWS can be used as a full
control-plane cloud.

Bootstrap chooses only the Terraform backend/operator environment. It does not
change DNS ownership. DNS is controlled separately by `terraform/config/dns.json`
through `dns.primary_cloud`.

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

Optional: add this to `~/.bashrc` so new shells load it automatically:

```bash
if [ -f /mnt/d/Internship/coin-ops-local/coin-ops/local/generated-gcp-env.sh ]; then
  source /mnt/d/Internship/coin-ops-local/coin-ops/local/generated-gcp-env.sh
fi
```

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

For an AWS-only end-to-end deploy where secrets live in AWS:

1. Set `clouds.control_plane = "aws"`, `clouds.secret_backend = "aws"`, and
   `clouds.enabled = ["aws"]` in `terraform/config/clouds.json`.
2. Run `terraform/bootstrap-aws.sh`.
3. Source `local/generated-aws-env.sh`.
4. Fill `terraform/bootstrap.secrets.auto.tfvars`.
5. Run `terraform init -reconfigure`.
6. Run `terraform apply -var='seed_secret_manager=true'`.
7. Run provision and deploy.

This does not assign the root DNS domain to AWS unless
`terraform/config/dns.json` also sets `dns.primary_cloud = "aws"`. If
`dns.primary_cloud` remains `gcp`, AWS should be validated through
`terraform output -json public_endpoints` and direct public IP HTTPS checks.

### 6. Provision and deploy

```bash
cd /mnt/d/Internship/coin-ops-local/coin-ops
ansible-playbook -i ansible/inventory ansible/provision.yml
ansible-playbook -i ansible/inventory ansible/deploy.yml
```

Current image-aware behavior:

- `app-1` and `app-2` may use the `coinops-app-host` golden image profile
- when they do, provisioning skips most of the baked host-preparation work from the `common` and `docker` roles
- provisioning now validates the baked contract on those hosts instead of reinstalling it silently
- `jump-host` still runs the full provisioning path
- when `internal_tls_enabled=true`, `app-1` reaches `app-2` through an internal TLS gateway on port `8443` instead of direct plain HTTP to `8000/8080`

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
- `TLS_MODE=certbot` requires a real public domain.
- `clouds.secret_backend` controls which cloud Ansible reads secrets from during deploy.
- AWS RDS defaults are lab/free-plan oriented: automated backups are disabled with `database.cloud_profiles.aws.backup_retention_period=0`. Raise this value only when the account plan/cost model allows it.
- `deploy.certbot.staging` in `terraform/config/deploy.json` controls whether certbot requests staging certificates by default.
- set `deploy.certbot.staging=true` for repeated validation; keep it `false` only when production certificate issuance is intentional
- on golden-image app hosts, `ansible/provision.yml` should validate Docker, UTC timezone, `systemd-timesyncd`, `ufw`, and common CLI tools rather than reinstall them

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
# default supported path
bash bootstrap-gcp.sh
grep -n 'backend "gcs"' backend.active.tf

# AWS control-plane rehearsal in a disposable AWS account/profile
bash bootstrap-aws.sh
grep -n 'backend "s3"' backend.active.tf
grep -n 'use_lockfile = true' backend.active.tf
```

Validate planning scenarios by changing only split JSON files under `terraform/config/`:

- `clouds.enabled = ["gcp"]`
- `clouds.enabled = ["aws"]`
- `clouds.enabled = ["gcp", "aws"]`
- `instances.<name>.clouds` set for one mixed-placement VM
- `clouds.secret_backend = "gcp"`
- `clouds.secret_backend = "aws"`
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
- `public_endpoints` contains `direct_url` for every public UI cloud, including when DNS is disabled or Cloudflare credentials are absent
- `database_endpoints` contains managed PostgreSQL metadata for every enabled cloud
- `terraform/config/ansible-runtime.json` contains `database.host`, `database.port`, `database.name`, `database.user`, and `database.managed` for every enabled cloud

For direct IP checks, use HTTPS on port `443`:

```bash
terraform output -json public_endpoints
curl -k https://<public-ip>/health
```

Browsers will warn because the certificate is issued for `APP_DOMAIN` or a self-signed DNS name, not for the raw IP address. That warning is expected for IP-only validation.

Validate Ansible after Terraform has produced inventory artifacts:

```bash
cd ..
ansible-inventory -i ansible/inventory --graph
ansible-playbook -i ansible/inventory ansible/provision.yml --syntax-check
ansible-playbook -i ansible/inventory ansible/deploy.yml --syntax-check
```

The inventory graph should contain cloud groups and role groups such as
`gcp`, `aws`, `role_app_ui`, `role_app_backend`, `role_jump_host`, and
`role_nat`.

Provisioning intentionally uses small batches and disables SSH ControlMaster in
Ansible. This keeps first-boot runs stable through bastion hosts after
cloud-init, UFW, and package-manager changes. If SSH is reachable manually but
Ansible reports a transient `Connection timed out during banner exchange`, rerun
the playbook once and keep `provisioning.host_batch_size` /
`provisioning.workload_batch_size` conservative in `terraform/config/deploy.json`.

For AWS runtime parity, verify that the rendered `DATABASE_URL` contains the RDS
host rather than an empty host or local Unix socket fallback:

```bash
ssh -F terraform/config/ssh_config coinops-aws-app-2
sudo docker compose -f /opt/cognitor/history/compose.yaml exec -T history-consumer python - <<'PY'
import os
from urllib.parse import urlparse
p = urlparse(os.environ["DATABASE_URL"])
print("scheme:", p.scheme)
print("host:", p.hostname)
print("port:", p.port)
print("db:", p.path)
PY
```

## Correctly Destroy Infrastructure Without Affecting Important Parts

Important non-compute infrastructure is protected with Terraform hard guards:

- Cloud SQL / RDS networking and database resources
- Secret Manager / Secrets Manager secret containers

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
  -target=local_file.hosts \
  -target=local_file.ssh_config \
  -target=local_file.ansible_runtime \
  -target=null_resource.sync_ssh_config
```

This preserves:

- Secret Manager / Secrets Manager
- Cloud SQL / RDS
- private service networking for Cloud SQL
- the VPC and firewall layers

The equivalent Make target is:

```bash
make tf-destroy-compute TF_DESTROY_ARGS='-auto-approve'
```

If you also want to remove public DNS records while preserving stateful infrastructure:

```bash
terraform destroy \
  -target=cloudflare_record.root_a \
  -target=cloudflare_record.www_cname
```

## Secondary Start of Infrastructure

Use this when compute was destroyed but stateful infrastructure was intentionally kept.

### 1. Load the generated environment

```bash
cd /mnt/d/Internship/coin-ops-local/coin-ops
source local/generated-gcp-env.sh
```

### 2. Recreate infrastructure

```bash
cd terraform
terraform apply
```

Because cloud secret managers and managed PostgreSQL still exist, this is a normal apply. Do not use `seed_secret_manager=true` unless you are intentionally reseeding or rotating secrets.

### 3. Re-provision and re-deploy

```bash
cd ..
ansible-playbook -i ansible/inventory ansible/provision.yml
ansible-playbook -i ansible/inventory ansible/deploy.yml
```

## Full Destroy of Infrastructure

Use this only when you intentionally want to remove everything, including stateful resources.

### 1. Load the generated environment

```bash
cd /mnt/d/Internship/coin-ops-local/coin-ops
source local/generated-gcp-env.sh
```

### 2. Run the deliberate full-destroy helper

This helper creates a temporary Terraform copy, removes GCP/AWS hard destroy
protections there, and runs `terraform destroy` against the same backend state.
The checked-in Terraform files remain unchanged.

```bash
cd terraform
bash full-destroy.sh --yes-really-destroy-stateful
```

This allows Terraform to delete:

- Secret Manager / Secrets Manager secrets and their versions
- Cloud SQL / RDS
- private service networking created for managed PostgreSQL
- compute, network, and local generated Terraform artifacts managed by state

AWS RDS final snapshots are disabled only inside the temporary full-destroy copy
so repeated lab teardowns do not collide on snapshot names.

You can pass through normal destroy flags if needed:

```bash
bash full-destroy.sh --yes-really-destroy-stateful -auto-approve
```

### 3. Rebuild after full destroy

After a full destroy, cloud secret managers no longer exist. The next start must repeat the initial seeding flow:

```bash
terraform apply -var='seed_secret_manager=true'
```

Then re-run provision and deploy.

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

## Troubleshooting Notes

### `terraform init` fails with `unexpected end of JSON input`

Validate the generated service account key:

```bash
python3 -m json.tool /mnt/d/Internship/coin-ops-local/coin-ops/terraform/sa-key.json
```

If it fails, regenerate the key by rerunning bootstrap with a valid human `gcloud` account.

### `terraform apply` fails because secret manager versions are missing

That means you are doing a fresh build after full destroy or after deleting secrets manually. Re-seed first:

```bash
terraform apply -var='seed_secret_manager=true'
```

### `terraform destroy` fails because protected resources cannot be deleted

That is expected for direct destroy operations against the checked-in Terraform configuration. Use the dedicated helper instead:

```bash
cd /mnt/d/Internship/coin-ops-local/coin-ops/terraform
bash full-destroy.sh --yes-really-destroy-stateful
```

### Ansible inventory does not show GCP hosts

Make sure you have sourced:

```bash
source local/generated-gcp-env.sh
```

and confirm:

```bash
ansible --version
ansible-inventory -i ansible/inventory/inventory.gcp_compute.yml --graph
```

### `TLS_MODE=certbot` fails

Check all of these:

- `APP_DOMAIN` is a real public domain
- `cloudflare_api_token` is valid
- Cloudflare DNS is reachable
- Cloudflare proxy is enabled only after DNS and origin are ready
