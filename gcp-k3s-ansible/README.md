# GCP K3s Ansible Track

This directory is a separate deployment track for:

- Terraform-managed GCP infrastructure
- Ansible-managed K3s installation
- Ansible-managed platform/application deployment

The intent is to keep this flow isolated from:

- `terraform.gcp.aws/` multi-cloud VM + Compose flow
- `terraform.kubespray.aws/` AWS + Kubespray flow

## Structure

```text
gcp-k3s-ansible/
|-- terraform/   # GCP network, VM, firewall, bastion, public Traefik LB
|-- ansible/     # inventory, playbooks, roles
`-- docs/        # track-specific notes
```

## Architecture

```text
Terraform
  -> VPC / subnet / Cloud NAT / bastion / 3 private K3s nodes / public LB

Ansible provision
  -> base OS preparation on nodes

Ansible install
  -> K3s control-plane cluster

Ansible platform
  -> cert-manager / ClusterIssuer
  -> Homepage (public)
  -> Headlamp (private-only)
  -> Coin-Ops (public)
```

Public flow:

```text
Browser
  -> Cloudflare DNS
  -> GCP public IP / load balancer
  -> Traefik
  -> Homepage Ingress
  -> Homepage Service
  -> Homepage Pod
```

Private admin flow:

```text
Laptop
  -> SSH tunnel
  -> bastion
  -> private K3s node
  -> Headlamp NodePort
  -> Headlamp Pod
```

## Defaults

Common non-secret values are now defined in the role defaults that use them, including:

- public hosts for `Homepage` and `Coin-Ops`
- Cloudflare zone and proxy mode
- default image tag
- Let's Encrypt email
- TLS issuer name
- fixed Traefik NodePorts

Secrets are expected from GCP Secret Manager by default:

- `coinops-db-password`
- `coinops-rabbitmq-password`
- `coinops-ghcr-token`
- `coinops-cloudflare-api-token`

The `homepage.yml` and `coinops.yml` playbooks first try environment variables and then fall back to GCP Secret Manager through `gcloud secrets versions access latest`.

What still needs to exist locally:

- `gcloud`
- an active GCP login
- access to project `brave-framework-494704-e6`
- permission to read the listed secrets

## Terraform State Migration

This track can migrate local `terraform.tfstate` into a GCS backend.

1. Create a dedicated bucket once:

```bash
gcloud storage buckets create gs://brave-framework-494704-e6-tfstate \
  --project=brave-framework-494704-e6 \
  --location=europe-central2 \
  --uniform-bucket-level-access
```

2. Enable object versioning:

```bash
gcloud storage buckets update gs://brave-framework-494704-e6-tfstate --versioning
```

3. Prepare backend config:

```bash
cd /home/valentyn/Test/coin-ops/gcp-k3s-ansible/terraform
cp backend.hcl.example backend.hcl
```

4. Migrate the existing local state:

```bash
terraform init -reconfigure -backend-config=backend.hcl -migrate-state
```

After that, Terraform will use GCS for state instead of the local `terraform.tfstate` file.

## End-to-End Runbook

### 1. Terraform infrastructure

```bash
cd /home/valentyn/Test/coin-ops/gcp-k3s-ansible/terraform
terraform init
terraform apply
```

Fill `terraform.tfvars` at least with:

- `project_id`
- `region`
- `zone`
- `ssh_public_key_path`

`allowed_source_cidr` is optional. If you omit it, Terraform detects your current external IP during `apply` and uses that for SSH and K3s API firewall rules.

### 2. Generate Ansible inventory

Terraform now writes [ansible/inventory.gcp.generated](/home/valentyn/Test/coin-ops/gcp-k3s-ansible/ansible/inventory.gcp.generated) automatically during `apply`.

### 3. Verify SSH connectivity

```bash
cd ../ansible
ansible -i inventory.gcp.generated all -m ping
```

### 4. Prepare nodes

```bash
ansible-playbook -i inventory.gcp.generated k3s-provision.yml
```

### 5. Install K3s

```bash
ansible-playbook -i inventory.gcp.generated k3s-install.yml
```

### 6. Connect kubectl

In one terminal:

```bash
cd ../terraform
terraform output -raw kubectl_tunnel_command
```

Run the printed command and keep that terminal open.

In another terminal:

```bash
kubectl get nodes
kubectl get pods -A
```

### 7. Verify Traefik public endpoint

```bash
cd /home/valentyn/Test/coin-ops/gcp-k3s-ansible/terraform
terraform output -raw traefik_public_ip
curl -H 'Host: homepage.smolyakov-devops.pp.ua' http://$(terraform output -raw traefik_public_ip)
```

### 8. Deploy Homepage

```bash
cd /home/valentyn/Test/coin-ops/gcp-k3s-ansible/ansible
ANSIBLE_LOCAL_TEMP=/tmp/ansible-local \
ANSIBLE_REMOTE_TEMP=/tmp/ansible-remote \
ansible-playbook -i inventory.gcp.generated homepage.yml
```

Check:

```bash
kubectl get pods -n homepage
kubectl get svc -n homepage
kubectl get ingress -n homepage
```

Validate:

```bash
dig +short homepage.smolyakov-devops.pp.ua
```

### 9. Install cert-manager

```bash
cd /home/valentyn/Test/coin-ops/gcp-k3s-ansible/ansible
ANSIBLE_LOCAL_TEMP=/tmp/ansible-local \
ANSIBLE_REMOTE_TEMP=/tmp/ansible-remote \
ansible-playbook -i inventory.gcp.generated cert-manager.yml
```

### 10. Install cert-manager and apply ClusterIssuer

```bash
cd /home/valentyn/Test/coin-ops/gcp-k3s-ansible/ansible
ANSIBLE_LOCAL_TEMP=/tmp/ansible-local \
ANSIBLE_REMOTE_TEMP=/tmp/ansible-remote \
ansible-playbook -i inventory.gcp.generated cert-manager.yml
```

Check:

```bash
kubectl get certificate -A
kubectl get certificaterequest -A
```

### 11. Deploy Headlamp

```bash
cd /home/valentyn/Test/coin-ops/gcp-k3s-ansible/ansible
ANSIBLE_LOCAL_TEMP=/tmp/ansible-local \
ANSIBLE_REMOTE_TEMP=/tmp/ansible-remote \
ansible-playbook -i inventory.gcp.generated headlamp.yml
```

Check:

```bash
kubectl get pods -n headlamp
kubectl get svc -n headlamp
```

### 12. Access Headlamp

Create token:

```bash
kubectl create token headlamp -n headlamp
```

Open private tunnel:

```bash
cd /home/valentyn/Test/coin-ops/gcp-k3s-ansible/terraform
terraform output -raw headlamp_tunnel_command
```

Run the printed command and keep it open.

Then open:

```text
http://127.0.0.1:30082
```

### 13. Deploy Coin-Ops

```bash
cd /home/valentyn/Test/coin-ops/gcp-k3s-ansible/ansible
ANSIBLE_LOCAL_TEMP=/tmp/ansible-local \
ANSIBLE_REMOTE_TEMP=/tmp/ansible-remote \
ansible-playbook -i inventory.gcp.generated coinops.yml
```

Check:

```bash
kubectl get pods -n coinops
curl -I https://homepage.smolyakov-devops.pp.ua
curl -I https://app.smolyakov-devops.pp.ua
curl https://app.smolyakov-devops.pp.ua/api/health
curl https://app.smolyakov-devops.pp.ua/history-api/health
```

## Notes

- This track stays Ansible-driven after infrastructure creation.
- `Homepage` is public through `Traefik + GCP load balancer + Cloudflare`.
- `Coin-Ops` is public through the same path.
- `Headlamp` is private-only through `bastion + SSH tunnel`.
- Traefik NodePorts are pinned in Ansible and matched by Terraform, so they should stay stable across rebuilds.
