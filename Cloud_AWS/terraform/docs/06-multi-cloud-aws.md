# Multi-Cloud Infrastructure — GCP + AWS

## Task

Deploy the same jump host architecture on both GCP and AWS using Terraform. Same patterns, same module structure, same YAML config approach. Switching between clouds = changing directory.

---

## Architecture — Same on Both Clouds

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

Both clouds produce the same functional result: 1 jump host with public IP, 3 internal VMs without public IPs, SSH on port 9922, user `marta_ops`, agent forwarding.

---

## How to Switch Between Clouds

It's two separate Terraform deployments. Switching is just changing directory:

```bash
# Deploy on GCP
cd Cloud_GCP/terraform
terraform apply

# Deploy on AWS
cd Cloud_AWS/terraform
terraform apply

# Destroy GCP only
cd Cloud_GCP/terraform
terraform destroy

# Destroy AWS only
cd Cloud_AWS/terraform
terraform destroy
```

Each has its own state file, its own credentials, its own provider. They don't interfere with each other. You can run both simultaneously or just one.

---

## How to Show Both Working

### GCP

```bash
cd /d/DevOps_internship/coin-ops/Cloud_GCP/terraform
terraform output
```

Shows GCP IPs. Connect:

```bash
eval $(ssh-agent -s)
ssh-add ~/.ssh/id_ed25519
ssh -A -p 9922 marta_ops@<GCP_JUMP_HOST_IP>
# from jump host:
ssh -p 9922 marta_ops@<GCP_INTERNAL_VM_IP>
```

### AWS

```bash
cd /d/DevOps_internship/coin-ops/Cloud_AWS/terraform
terraform output
```

Shows AWS IPs. Connect:

```bash
ssh -A -p 9922 marta_ops@<AWS_JUMP_HOST_IP>
# from jump host:
ssh -p 9922 marta_ops@<AWS_INTERNAL_VM_IP>
```

Same commands, same user, same port — different cloud. That's the point of multi-cloud: the operational workflow is identical.

---

## Resource Mapping — GCP vs AWS

| Concept | GCP | AWS |
|---|---|---|
| Virtual network | `google_compute_network` (VPC) | `aws_vpc` |
| IP range | `google_compute_subnetwork` | `aws_subnet` |
| Internet access | Automatic | `aws_internet_gateway` + `aws_route_table` (must be explicit) |
| Virtual machine | `google_compute_instance` | `aws_instance` (EC2) |
| Firewall | `google_compute_firewall` (network-level, tag-based) | `aws_security_group` (instance-level, SG-based) |
| Public IP | `access_config {}` block on network interface | `associate_public_ip_address = true` |
| SSH key | `metadata.ssh-keys` (creates user automatically) | `aws_key_pair` + `user_data` script (manual user creation) |
| Machine image | Image name: `ubuntu-os-cloud/ubuntu-2404-lts-amd64` | AMI ID: `ami-0084a47cc718c111a` (region-specific) |
| Machine size | `machine_type = "e2-micro"` | `instance_type = "t3.micro"` |
| First-boot script | `metadata_startup_script` | `user_data` |
| Credentials | `key.json` (service account) | Access Key ID + Secret Access Key (IAM user) |

---

## Key Differences Explained

### Networking

**GCP:** Create a VPC and subnet — internet access works automatically. Firewall rules are separate resources that target VMs by tags.

**AWS:** Create a VPC, subnet, AND explicitly an Internet Gateway + Route Table. Without these, even VMs with public IPs can't reach the internet. Security Groups replace firewall rules and attach directly to instances.

In the Terraform code, GCP networking is 2 resources (VPC + subnet). AWS networking is 5 resources (VPC + 2 subnets + Internet Gateway + Route Table + Route Table Association).

### Subnets

**GCP:** One subnet for all VMs. Public/private is controlled by `access_config` on each VM.

**AWS:** Two subnets — public (for jump host, routed to Internet Gateway) and private (for internal VMs, no internet route). The subnet determines whether a VM can have a public IP.

### SSH Key Management

**GCP:** Add public key to VM metadata with a username. GCP automatically creates that user on the VM. One line in Terraform.

**AWS:** Upload public key as a Key Pair resource. AWS puts the key in the default `ubuntu` user's authorized_keys. To use a custom user (`marta_ops`), the user_data script must manually: create the user with `useradd`, copy the authorized_keys, set permissions, add sudo access.

### Firewall vs Security Groups

**GCP:** Firewall rules are network-level. You create a rule and use `target_tags` to specify which VMs it applies to. VMs are tagged with `["jump-host"]` or `["internal"]`.

**AWS:** Security Groups are instance-level. You create a Security Group, define ingress/egress rules, and attach it to instances. Internal SG references the jump host SG by ID (not by tag): `security_groups = [aws_security_group.jump_host.id]`.

### First-Boot Script

**GCP:** `metadata_startup_script` runs by Google's metadata script runner, separate from cloud-init. Needs `cloud-init status --wait` to avoid race conditions.

**AWS:** `user_data` IS cloud-init. The script runs as part of cloud-init, so `cloud-init status --wait` causes a deadlock (waiting for itself). Must NOT include it in AWS.

---

## File Structure

```
coin-ops/
├── Cloud_GCP/
│   └── terraform/
│       ├── config.yaml           ← GCP VM definitions
│       ├── main.tf               ← GCP resources + module calls
│       ├── modules/vm/           ← GCP VM module
│       ├── provider.tf           ← Google provider
│       ├── variables.tf          ← credentials_file only
│       ├── terraform.tfvars      ← GCP credentials (not in Git)
│       └── backend.tf            ← GCS remote state
│
├── Cloud_AWS/
│   └── terraform/
│       ├── config.yaml           ← AWS VM definitions
│       ├── main.tf               ← AWS resources + module calls
│       ├── modules/vm/           ← AWS VM module
│       ├── provider.tf           ← AWS provider
│       ├── variables.tf          ← access_key + secret_key
│       ├── terraform.tfvars      ← AWS credentials (not in Git)
│       └── .gitignore            ← excludes secrets and state
```

Same structure, same patterns. The YAML config has the same `general` + `vms` blocks. The module has the same interface (name, tags, public_ip, disk_size). Only the provider-specific implementation differs.

---

## AWS Implementation Details

### IAM User (AWS equivalent of GCP Service Account)

| | GCP | AWS |
|---|---|---|
| Name | `terraform-sa` | `terraform-sa` |
| Type | Service Account | IAM User |
| Credentials | `key.json` file | Access Key ID + Secret Access Key |
| Permissions | `compute.admin`, `storage.admin` | `AmazonEC2FullAccess`, `AmazonVPCFullAccess` |
| Where stored | `Cloud_GCP/key.json` (gitignored) | `Cloud_AWS/terraform/terraform.tfvars` (gitignored) |

### config.yaml (AWS version)

```yaml
general:
  region: "eu-central-1"
  instance_type: "t3.micro"
  ami: "ami-0084a47cc718c111a"
  disk_size: 10
  ssh_port: "9922"
  ops_user: "marta_ops"

vms:
  jump-host:
    tags:
      - "jump-host"
    public_ip: true
  internal-vm-1:
    tags:
      - "internal"
    public_ip: false
  internal-vm-2:
    tags:
      - "internal"
    public_ip: false
  internal-vm-3:
    tags:
      - "internal"
    public_ip: false
```

Same structure as GCP. Different field names: `instance_type` instead of `machine_type`, `ami` instead of `image`.

### VM Module — user_data script

```bash
#!/bin/bash
if [ -f /etc/ssh/sshd_config.d/custom-port.conf ]; then
  echo "SSH already configured, skipping"
  exit 0
fi

# Create operational user (AWS doesn't do this from metadata)
useradd -m -s /bin/bash marta_ops
mkdir -p /home/marta_ops/.ssh
cp /home/ubuntu/.ssh/authorized_keys /home/marta_ops/.ssh/
chown -R marta_ops:marta_ops /home/marta_ops/.ssh
echo "marta_ops ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/marta_ops

# Change SSH port
systemctl disable --now ssh.socket
echo "Port 9922" > /etc/ssh/sshd_config.d/custom-port.conf
systemctl enable ssh.service
systemctl restart ssh.service
```

Key differences from GCP script:
- No `cloud-init status --wait` (causes deadlock in AWS)
- Manual user creation with `useradd` (GCP creates users from metadata automatically)
- Copies SSH key from `ubuntu` user to `marta_ops` (AWS puts the key pair in `ubuntu` by default)

---

## Problems Encountered

### 1. `t2.micro` not free tier eligible

**Error:** `The specified instance type is not eligible for Free Tier`

**Cause:** AWS Free Plan (the new 6-month free plan) doesn't include `t2.micro`. Only `t3.micro` is eligible.

**Fix:** Changed `instance_type` from `t2.micro` to `t3.micro` in `config.yaml`.

### 2. `cloud-init status --wait` deadlock

**Error:** Script hung with dots (`...........`) in the log, SSH port never changed.

**Cause:** In AWS, `user_data` is executed BY cloud-init. Running `cloud-init status --wait` inside a cloud-init script waits for itself to finish — infinite loop.

In GCP, `metadata_startup_script` runs via Google's own script runner (separate from cloud-init), so waiting for cloud-init is safe.

**Fix:** Removed `cloud-init status --wait` from the AWS module's user_data.

### 3. user_data doesn't re-run on existing instances

**Problem:** After fixing the module code, `terraform apply` updated the `user_data` attribute but didn't recreate the VMs. The old (broken) script was already executed on first boot — AWS never re-runs user_data.

**Fix:** Force recreation with:

```bash
terraform apply -replace="module.vm[\"internal-vm-1\"].aws_instance.vm" \
  -replace="module.vm[\"internal-vm-2\"].aws_instance.vm" \
  -replace="module.vm[\"internal-vm-3\"].aws_instance.vm" \
  -replace="module.vm[\"jump-host\"].aws_instance.vm"
```

**Lesson:** `user_data` (AWS) and `metadata_startup_script` (GCP) only run on first boot. Changing the script in Terraform doesn't affect running instances. You must recreate them.

### 4. C: drive full — Terraform plugin download failed

**Error:** `There is not enough space on the disk` when downloading AWS provider (~400MB).

**Fix:** Redirected Terraform temp and plugin cache to D: drive:

```bash
export TMP=/d/tmp
export TEMP=/d/tmp
export TF_PLUGIN_CACHE_DIR=/d/tmp/terraform-plugins
```

### 5. AWS public IP changes on stop/start

**Problem:** After `terraform apply` modified instances, the jump host got a new public IP.

**Cause:** AWS assigns ephemeral public IPs. Unlike GCP where IPs persist unless the VM is deleted, AWS releases the IP when an instance is stopped. For a stable IP, you'd need an Elastic IP (a separate AWS resource).

**For this task:** We just use `terraform output` to get the current IP.

---

## Current State

### GCP (Cloud_GCP)

| VM | External IP | Internal IP | Port | User |
|---|---|---|---|---|
| jump-host | 34.116.244.13 | 10.0.1.31 | 9922 | marta_ops |
| internal-vm-1 | — | 10.0.1.33 | 9922 | marta_ops |
| internal-vm-2 | — | 10.0.1.32 | 9922 | marta_ops |
| internal-vm-3 | — | 10.0.1.34 | 9922 | marta_ops |

### AWS (Cloud_AWS)

| VM | External IP | Internal IP | Port | User |
|---|---|---|---|---|
| jump-host | 3.121.235.99 | 10.0.1.253 | 9922 | marta_ops |
| internal-vm-1 | — | 10.0.2.215 | 9922 | marta_ops |
| internal-vm-2 | — | 10.0.2.205 | 9922 | marta_ops |
| internal-vm-3 | — | 10.0.2.31 | 9922 | marta_ops |

---

## Key DevOps Lessons

1. **Multi-cloud = same patterns, different implementations.** You can't share Terraform code between providers, but you can share the architecture, naming conventions, module interfaces, and YAML config structure.

2. **Each cloud has quirks.** AWS needs explicit Internet Gateways and Route Tables. GCP does it automatically. AWS needs manual user creation in user_data. GCP creates users from metadata. Knowing these differences is core cloud engineering knowledge.

3. **user_data / startup scripts run once.** Changing the script in Terraform doesn't fix running VMs. You must recreate them. This applies to both GCP and AWS.

4. **cloud-init behaves differently per cloud.** In GCP, the startup script runs separately from cloud-init. In AWS, user_data IS cloud-init. This caused the deadlock when we used `cloud-init status --wait` in AWS.

5. **Security Groups vs Firewall Rules.** GCP firewalls are network-level and use tags. AWS Security Groups are instance-level and reference each other by ID. Different mental model, same security result.

6. **Credentials management.** GCP uses a JSON key file. AWS uses two strings (Access Key + Secret Key). Both are stored outside Git, both follow least-privilege principles, both are created for a dedicated automation user (not your personal account).
