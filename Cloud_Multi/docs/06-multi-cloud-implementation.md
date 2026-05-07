# Multi-Cloud Infrastructure — Unified Terraform (GCP + AWS)

## Overview

Single Terraform codebase that deploys identical jump host architecture to either GCP or AWS. Switching between clouds = changing one line in `config.yaml`.

---

## Architecture

```
Your laptop
    │
    │  ssh -p 9922 marta_ops@<public_ip>
    │
    ▼
jump-host (public IP, port 9922)
    │
    │  agent forwarding
    │
    ├── internal-vm-1 (private IP only)
    ├── internal-vm-2 (private IP only)
    └── internal-vm-3 (private IP only)
```

Same architecture on both clouds: 1 jump host with public IP, 3 internal VMs without public IPs, SSH on port 9922, operational user `marta_ops`, agent forwarding.

---

## How Cloud Switching Works

One config file, one line controls which cloud to deploy to:

```yaml
general:
  cloud: "gcp"    # change to "aws" to deploy on AWS
```

Every module checks this value:

```hcl
# GCP resources — only created when cloud is "gcp"
count = var.config.general.cloud == "gcp" ? 1 : 0

# AWS resources — only created when cloud is "aws"
count = var.config.general.cloud == "aws" ? 1 : 0
```

When `count = 0`, Terraform skips the resource entirely. GCP modules produce zero resources when cloud is "aws" and vice versa. The logic lives inside each module — the root `main.tf` just passes the config.

Switching flow:

```bash
# Edit config.yaml: cloud: "gcp" → cloud: "aws"
terraform apply
# GCP resources destroyed, AWS resources created
```

---

## File Structure

```
Cloud_Multi/
└── terraform/
    ├── config.yaml                ← single config for both clouds
    ├── main.tf                    ← root module, calls all child modules
    ├── outputs.tf                 ← IPs and SSH command
    ├── provider.tf                ← both GCP and AWS providers
    ├── variables.tf               ← only credentials (secrets)
    ├── terraform.tfvars           ← credentials (not in Git)
    ├── backend.tf                 ← remote state in GCS
    └── modules/
        ├── gcp_network/           ← VPC + subnet
        ├── gcp_security/          ← firewall rules
        ├── gcp_vm/                ← GCP compute instances
        ├── aws_network/           ← VPC + subnets + IGW + routes
        ├── aws_security/          ← security groups
        └── aws_vm/                ← AWS EC2 instances
```

---

## config.yaml

```yaml
general:
  cloud: "gcp"
  project_id: "devops-intern-penina"
  regions:
    gcp:
      region: "europe-central2"
      zone: "europe-central2-a"
    aws:
      region: "eu-central-1"
      zone: "eu-central-1b"
  disk_size: 10
  ssh_port: "9922"
  ops_user: "marta_ops"
  image:
    gcp: "ubuntu-os-cloud/ubuntu-2404-lts-amd64"
    aws: "ami-0084a47cc718c111a"

sizes:
  small:
    gcp: "e2-micro"
    aws: "t3.micro"

vms:
  jump-host:
    size: small
    tags: ["jump-host"]
    public_ip: true
  internal-vm-1:
    size: small
    tags: ["internal"]
    public_ip: false
  internal-vm-2:
    size: small
    tags: ["internal"]
    public_ip: false
  internal-vm-3:
    size: small
    tags: ["internal"]
    public_ip: false
```

### Config Design Decisions

**Size dictionary** — VMs reference abstract sizes (`small`, `medium`), not cloud-specific machine types. The dictionary maps each size to the correct type per cloud. Adding a new cloud = one line per size, not editing every VM.

**Region dictionary** — structured `regions.gcp.region` / `regions.aws.zone` instead of flat `gcp_region`, `aws_region`. Both clouds have regions and zones — the structure reflects this.

**Image mapping** — `image.gcp` and `image.aws` in one place. GCP uses image names, AWS uses AMI IDs (region-specific).

**Override pattern** — VMs inherit from `general` defaults. Per-VM overrides via `try()`:

```hcl
disk_size = try(each.value.disk_size, var.config.general.disk_size)
```

---

## Module Architecture

### How Modules Receive Data

Each module receives the entire config object plus cross-module outputs:

```hcl
module "gcp_vm" {
  source         = "./modules/gcp_vm"
  config         = local.config                    # everything from YAML
  subnetwork     = module.gcp_network.subnet_id    # from another module
  ssh_public_key = file("~/.ssh/id_ed25519.pub")   # from filesystem
}
```

Values from config.yaml → passed as one `config` object. Values from other modules (IDs created at runtime) → passed individually. The module reads what it needs internally: `var.config.general.cloud`, `var.config.vms`, etc.

### Module Responsibilities

| Module | Creates | Cloud |
|---|---|---|
| `gcp_network` | VPC, subnet | GCP |
| `gcp_security` | 3 firewall rules (external SSH, internal SSH, internal traffic) | GCP |
| `gcp_vm` | Compute instances with SSH hardening | GCP |
| `aws_network` | VPC, 2 subnets, Internet Gateway, Route Table | AWS |
| `aws_security` | 2 security groups (jump host, internal) | AWS |
| `aws_vm` | EC2 instances with SSH hardening + user creation | AWS |

### for_each Inside Modules

The root module calls each VM module once. The module iterates internally:

```hcl
# Inside modules/gcp_vm/main.tf
resource "google_compute_instance" "vm" {
  for_each = var.config.general.cloud == "gcp" ? var.config.vms : {}
  name     = each.key
  # ...
}
```

If cloud is not "gcp", `for_each` receives an empty map — zero VMs created.

---

## Resource Mapping — GCP vs AWS

| Concept | GCP | AWS |
|---|---|---|
| Virtual network | VPC (auto-routes to internet) | VPC + Internet Gateway + Route Table (explicit) |
| Subnets | 1 regional subnet | 2 zonal subnets (public + private) |
| Firewall | Firewall rules (network-level, tag-based) | Security groups (instance-level, SG-referenced) |
| Public IP | `access_config {}` block | `associate_public_ip_address = true` |
| SSH key | `metadata.ssh-keys` (creates user automatically) | Key Pair + `user_data` script (manual user creation) |
| Machine type | `machine_type = "e2-micro"` | `instance_type = "t3.micro"` |
| Boot image | Image name | AMI ID (region-specific) |
| Startup script | `metadata_startup_script` (separate from cloud-init) | `user_data` (IS cloud-init) |
| Credentials | `key.json` (service account) | Access Key + Secret Key (IAM user) |

### Key Differences in Implementation

**Networking:** GCP networking = 2 resources (VPC + subnet). AWS = 6 resources (VPC + 2 subnets + IGW + Route Table + Association). AWS requires explicit internet routing.

**SSH user creation:** GCP creates users automatically from `metadata.ssh-keys`. AWS puts the key pair in the default `ubuntu` user — the startup script must manually create `marta_ops` with `useradd`, copy authorized_keys, set permissions, and add sudo access.

**Startup script execution:** GCP's `metadata_startup_script` runs via Google's script runner (separate from cloud-init). Needs `cloud-init status --wait` to prevent race conditions. AWS's `user_data` IS cloud-init — using `cloud-init status --wait` causes a deadlock (waiting for itself).

**SSH port change (Ubuntu 24.04):** Both clouds face the same socket activation issue. The startup script disables `ssh.socket` and runs SSH as a traditional service to respect the `Port 9922` config.

---

## Credentials

| | GCP | AWS |
|---|---|---|
| IAM entity | Service account `terraform-sa` | IAM user `terraform-sa` |
| Permissions | `compute.admin`, `storage.admin`, `iam.serviceAccountUser` | `AmazonEC2FullAccess`, `AmazonVPCFullAccess` |
| Credential format | JSON key file | Access Key ID + Secret Access Key |
| Stored in | `terraform.tfvars` → `gcp_credentials_file` path | `terraform.tfvars` → `aws_access_key` + `aws_secret_key` |
| In Git | Never | Never |

---

## How to Deploy

### Prerequisites

- Terraform installed
- GCP service account key (`key.json`)
- AWS IAM user access keys
- SSH key pair (`~/.ssh/id_ed25519`)

### Deploy to GCP

```bash
# Set cloud in config.yaml
cloud: "gcp"

# Deploy
cd Cloud_Multi/terraform
terraform init
terraform plan
terraform apply

# Get IPs
terraform output

# Connect
eval $(ssh-agent -s)
ssh-add ~/.ssh/id_ed25519
ssh -A -p 9922 marta_ops@<JUMP_HOST_IP>
ssh -p 9922 marta_ops@<INTERNAL_VM_IP>
```

### Switch to AWS

```bash
# Change one line in config.yaml
cloud: "aws"

# Apply — destroys GCP, creates AWS
terraform apply

# Get new IPs
terraform output

# Connect (same commands, different IP)
ssh -A -p 9922 marta_ops@<AWS_JUMP_HOST_IP>
ssh -p 9922 marta_ops@<AWS_INTERNAL_VM_IP>
```

### Adding a New VM

Edit `config.yaml` only:

```yaml
vms:
  monitoring:
    size: small
    tags: ["internal"]
    public_ip: false
```

Then `terraform apply`. Works on whichever cloud is currently selected.

### Destroy

```bash
terraform destroy
```

---

## Problems Encountered

### 1. Ubuntu 24.04 SSH Socket Activation

SSH stayed on port 22 despite config saying 9922. Cause: systemd's `ssh.socket` opens port 22 before sshd reads config. Fix: `systemctl disable --now ssh.socket` — sshd runs traditionally, reads config directly.

### 2. AWS user_data Deadlock

Startup script hung forever. Cause: `cloud-init status --wait` inside `user_data` waits for cloud-init (which IS user_data) to finish — infinite loop. Fix: removed `cloud-init status --wait` from AWS module.

### 3. user_data Doesn't Re-run

After fixing the module, `terraform apply` updated the attribute but didn't recreate VMs. Cause: AWS only runs user_data on first boot. Fix: `terraform apply -replace="module.vm[\"jump-host\"].aws_instance.vm"` to force recreation.

### 4. t2.micro Not Free Tier

AWS Free Plan requires `t3.micro`, not `t2.micro`. Fixed in size dictionary.

### 5. AWS Needs Manual User Creation

GCP creates users from SSH key metadata automatically. AWS doesn't — the startup script uses `useradd` to create `marta_ops`, copies `authorized_keys` from `ubuntu`, sets permissions and sudo access.
