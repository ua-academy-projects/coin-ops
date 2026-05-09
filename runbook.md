# Infrastructure Runbook

This runbook describes the supported lifecycle for the current GCP-first infrastructure flow.

The normal operator model is:

- bootstrap once with `terraform/bootstrap-gcp.sh`
- source `local/generated-env.sh`
- seed Secret Manager only when needed
- keep the built-in stateful-resource protections in place for normal work

## Prerequisites

- Run from WSL/Linux.
- Install Terraform, Ansible, `gcloud`, and Docker-compatible SSH tooling.
- Install Ansible collections:

```bash
cd /mnt/d/Internship/coin-ops-local/coin-ops
ansible-galaxy collection install -r ansible/requirements.yml
```

- Authenticate `gcloud` with a human/operator account before bootstrap:

```bash
gcloud auth login
gcloud auth list
```

Do not run bootstrap while the active `gcloud` account is the Terraform service account.

## Generated Local Files

`terraform/bootstrap-gcp.sh` generates these local gitignored files:

- `terraform/sa-key.json`
- `terraform/local.generated.auto.tfvars.json`
- `terraform/bootstrap.secrets.auto.tfvars`
- `ansible/vars/local.generated.json`
- `local/generated-env.sh`

These files replace the old repo `.env` workflow.

## Very First Start of Infrastructure

### 1. Review bootstrap defaults

Open `terraform/bootstrap-gcp.sh` and adjust the local defaults if needed:

- `PROJECT_ID`
- `REGION`
- `APP_DOMAIN`
- `TLS_MODE`
- `RUNTIME_BACKEND`
- `GHCR_USERNAME`
- image defaults

### 2. Run bootstrap

```bash
cd /mnt/d/Internship/coin-ops-local/coin-ops/terraform
bash bootstrap-gcp.sh
```

### 3. Fill the bootstrap secrets file

Edit `terraform/bootstrap.secrets.auto.tfvars` and replace the placeholder values:

- `db_password`
- `rabbitmq_password`
- `ghcr_token`
- `cloudflare_api_token`

### 4. Load the generated environment

```bash
cd /mnt/d/Internship/coin-ops-local/coin-ops
source local/generated-env.sh
```

Optional: add this to `~/.bashrc` so new shells load it automatically:

```bash
if [ -f /mnt/d/Internship/coin-ops-local/coin-ops/local/generated-env.sh ]; then
  source /mnt/d/Internship/coin-ops-local/coin-ops/local/generated-env.sh
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
- generates `terraform/config/ssh_config`
- generates `terraform/config/ansible-runtime.json`

### 6. Provision and deploy

```bash
cd /mnt/d/Internship/coin-ops-local/coin-ops
ansible-playbook -i ansible/inventory ansible/provision.yml
ansible-playbook -i ansible/inventory ansible/deploy.yml
```

### 7. Smoke-check the result

```bash
ansible-inventory -i ansible/inventory --graph
curl -I https://"$APP_DOMAIN"
curl https://"$APP_DOMAIN"/health
```

Notes:

- External port `80` is intentionally closed.
- Cloudflare proxy is the intended public entry point.
- `TLS_MODE=certbot` requires a real public domain.

## Correctly Destroy Infrastructure Without Affecting Important Parts

Important non-compute infrastructure is protected with Terraform hard guards:

- Cloud SQL networking and database resources
- Secret Manager secret containers

To remove only compute and compute-adjacent runtime artifacts, use targeted destroy:

```bash
cd /mnt/d/Internship/coin-ops-local/coin-ops
source local/generated-env.sh
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
source local/generated-env.sh
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
source local/generated-env.sh
```

### 2. Temporarily remove the hard protections

Terraform does not allow `prevent_destroy` to be toggled by a normal variable. For a deliberate full teardown, temporarily edit these files and remove or comment the `prevent_destroy = true` lifecycle blocks, and set `deletion_protection = false` on the Cloud SQL instance:

- `terraform/modules/gcp_database/main.tf`
- `terraform/modules/gcp_secrets/main.tf`

### 3. Destroy everything

```bash
cd terraform
terraform destroy
```

This allows Terraform to delete:

- Secret Manager secrets and their versions
- Cloud SQL
- private service networking created for Cloud SQL
- compute, network, and local generated Terraform artifacts managed by state

### 4. Restore protections and rebuild after full destroy

After the destroy finishes, restore the protection blocks you removed in the module files before the next normal apply.

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

### Ansible inventory does not show GCP hosts

Make sure you have sourced:

```bash
source local/generated-env.sh
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
