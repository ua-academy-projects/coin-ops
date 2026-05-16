# Infrastructure Runbook

This runbook describes the supported lifecycle for the current multi-cloud-ready infrastructure flow.

For exact GCP vs AWS support boundaries, see [MULTI_CLOUD_SCOPE.md](/D:/Internship/coin-ops-local/coin-ops/MULTI_CLOUD_SCOPE.md).

The normal operator model is:

- choose the control-plane cloud in `terraform/config/clouds.json`
- bootstrap once with the matching script, for example `terraform/bootstrap-gcp.sh`
- source the matching generated env, for example `local/generated-gcp-env.sh`
- seed Secret Manager only when needed
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

These files replace the old repo `.env` workflow.

`backend.active.tf` is intentionally generated rather than committed because Terraform backend blocks cannot read JSON locals directly.

Generated env files contain only local credentials and operator paths. Committed non-secret deploy settings such as domain, TLS mode, ports, and image tags stay in the split JSON files under `terraform/config/`.

## Very First Start of Infrastructure

### 1. Review SSOT config

Review the split SSOT files under `terraform/config/` and adjust the committed non-secret defaults if needed:

- `clouds.json`: `clouds.control_plane`, `clouds.enabled`, `clouds.default_instance_clouds`, `clouds.providers`, and `clouds.backends`
- `general.json`: project/user/SSH/region/image defaults
- `deploy.json`: domain, TLS/certbot policy, runtime backend, image defaults, ports, and Ansible provisioning defaults
- `dns.json`: `dns.primary_cloud` and Cloudflare defaults
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
support in the generated backend artifact.

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

### 5. Seed Secret Manager and create infrastructure

```bash
cd /mnt/d/Internship/coin-ops-local/coin-ops/terraform
terraform init
terraform apply -var='seed_secret_manager=true'
```

This first apply:

- creates or updates GCP Secret Manager secrets
- creates the infrastructure
- uses the explicit backend from `terraform/backend.active.tf`
- generates `terraform/config/ssh_config`
- generates `terraform/config/ansible-runtime.json`

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

## Correctly Destroy Infrastructure Without Affecting Important Parts

Important non-compute infrastructure is protected with Terraform hard guards:

- Cloud SQL networking and database resources
- Secret Manager secret containers

To remove only compute and compute-adjacent runtime artifacts, use targeted destroy:

```bash
cd /mnt/d/Internship/coin-ops-local/coin-ops
source local/generated-gcp-env.sh
cd terraform
terraform destroy \
  -target=module.gcp_nat_route \
  -target=module.gcp_instances \
  -target=local_file.hosts \
  -target=local_file.ssh_config \
  -target=local_file.ansible_runtime \
  -target=null_resource.sync_ssh_config
```

This preserves:

- Secret Manager
- Cloud SQL
- private service networking for Cloud SQL
- the VPC and firewall layers

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

Because Secret Manager and Cloud SQL still exist, this is a normal apply. Do not use `seed_secret_manager=true` unless you are intentionally reseeding or rotating secrets.

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

This helper creates a temporary Terraform copy, removes the hard destroy protections there, and runs `terraform destroy` against the same backend state. The checked-in Terraform files remain unchanged.

```bash
cd terraform
bash full-destroy.sh --yes-really-destroy-stateful
```

This allows Terraform to delete:

- Secret Manager secrets and their versions
- Cloud SQL
- private service networking created for Cloud SQL
- compute, network, and local generated Terraform artifacts managed by state

You can pass through normal destroy flags if needed:

```bash
bash full-destroy.sh --yes-really-destroy-stateful -auto-approve
```

### 3. Rebuild after full destroy

After a full destroy, Secret Manager no longer exists. The next start must repeat the initial seeding flow:

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

### `terraform apply` fails because Secret Manager secret versions are missing

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
