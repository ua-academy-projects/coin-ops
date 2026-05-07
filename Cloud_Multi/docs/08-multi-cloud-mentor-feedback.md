# Multi-Cloud Refactoring — Mentor Feedback & Improvements

## Context

After presenting the multi-cloud implementation (Cloud_Multi), the mentor reviewed the code and provided feedback. This document covers every question discussed, what was changed, and why.

---

## 1. Operational User (ops_user)

**Mentor's question:** If another team member uses your automation, will they also be `marta_ops`?

**Answer:** No. The username is defined in `config.yaml` under `general.ops_user`. A new team member changes it to their own name in one place — the config file. All modules read from `var.config.general.ops_user`, so the change propagates everywhere automatically. No hardcoded usernames in Terraform code.

This is the "single source of truth" principle — one place to define, many places to consume.

---

## 2. SSH Socket Activation (Ubuntu 24.04)

**Mentor's question:** Which files did you change, and what was the actual problem?

**The problem:** Ubuntu 24.04 introduced socket activation for SSH. Two things control the SSH port:

- `/etc/ssh/sshd_config` (and `/etc/ssh/sshd_config.d/*.conf`) — the traditional config, tells sshd what port to use
- `/lib/systemd/system/ssh.socket` — the new mechanism, where systemd opens port 22 BEFORE sshd even starts

The socket file overrides sshd_config. Writing `Port 9922` to the config did nothing because systemd already grabbed port 22 and handed connections to sshd. Sshd never read the config.

**The fix:** Disabled socket activation entirely:

```bash
systemctl disable --now ssh.socket    # turn off the new mechanism
systemctl enable ssh.service          # enable traditional SSH service
systemctl restart ssh.service         # restart to read config with Port 9922
```

**Files involved:**

| File | Action | Purpose |
|---|---|---|
| `/etc/ssh/sshd_config.d/custom-port.conf` | Created | Contains `Port 9922` |
| `/lib/systemd/system/ssh.socket` | Disabled | Was overriding our port config |
| `/lib/systemd/system/ssh.service` | Enabled | Runs SSH the traditional way, reads sshd_config |

**How to verify on a running VM:**

```bash
cat /etc/ssh/sshd_config.d/custom-port.conf     # shows Port 9922
sudo systemctl status ssh.socket                  # shows inactive (dead), disabled
sudo systemctl status ssh.service                 # shows active (running), enabled
sudo ss -tlnp | grep ssh                          # shows only port 9922
cat /lib/systemd/system/ssh.socket               # shows ListenStream=22 (the old override)
grep -n "Include" /etc/ssh/sshd_config            # shows Include sshd_config.d/*.conf
```

**Additional note — GCP vs AWS difference:**

In GCP, `metadata_startup_script` runs via Google's script runner — separate from cloud-init. Adding `cloud-init status --wait` is safe and prevents race conditions.

In AWS, `user_data` IS cloud-init. Running `cloud-init status --wait` inside a cloud-init script waits for itself — deadlock. Must NOT include it in AWS.

---

## 3. for_each — Inside or Outside the Module?

**Mentor's question:** Is `for_each` inside the module or in the root `main.tf`?

**Answer:** Inside the module. The root `main.tf` passes the entire `vms` map to the module. The module itself iterates:

```hcl
# Inside modules/gcp_vm/main.tf
resource "google_compute_instance" "vm" {
  for_each = var.config.general.cloud == "gcp" ? var.config.vms : {}
  name     = each.key
  # ...
}
```

The root module calls the VM module once. The module creates 4 VMs internally.

**Alternative approach (for_each outside):**

```hcl
# In root main.tf — call module once per VM
module "vm" {
  for_each = local.config.vms
  source   = "./modules/vm"
  name     = each.key
}
```

This approach calls the module 4 times, each creating 1 VM. Both are valid — the mentor confirmed the inside approach is correct for this project because the module handles the cloud-switching logic internally.

---

## 4. Size Dictionary

**Why it exists:**

Without dictionary — every VM specifies cloud-specific machine types:

```yaml
# Bad: hardcoded per cloud
vms:
  jump-host:
    gcp_machine_type: "e2-micro"
    aws_instance_type: "t3.micro"
```

Problem: adding Azure means editing every VM definition. The person editing YAML needs to know exact machine type names for every cloud.

With dictionary — VMs use abstract sizes:

```yaml
# Good: abstraction
sizes:
  small:
    gcp: "e2-micro"
    aws: "t3.micro"
  medium:
    gcp: "e2-medium"
    aws: "t3.medium"

vms:
  jump-host:
    size: small     # doesn't know about cloud-specific types
```

The person editing VMs thinks in abstractions: "this VM is small." The mapping to cloud-specific types is defined once in the dictionary. Adding Azure = one line per size: `azure: "Standard_B1s"`.

In Terraform, the lookup: `var.config.sizes[each.value.size][var.config.general.cloud]` — reads "small" → picks the right type for the current cloud.

---

## 5. Cloud Switching Logic

**Mentor's question:** How do resources get created in one cloud but not the other?

Every module checks the `cloud` variable:

```hcl
# GCP module — only creates if cloud is "gcp"
resource "google_compute_network" "vpc" {
  count = var.config.general.cloud == "gcp" ? 1 : 0
}

# AWS module — only creates if cloud is "aws"
resource "aws_vpc" "main" {
  count = var.config.general.cloud == "aws" ? 1 : 0
}
```

For VMs with `for_each`:

```hcl
# GCP VM module
resource "google_compute_instance" "vm" {
  for_each = var.config.general.cloud == "gcp" ? var.config.vms : {}
  # cloud is "aws" → empty map → nothing created
}
```

**What is a ternary?** `condition ? value_if_true : value_if_false` — one-line if/else. `count = var.config.general.cloud == "gcp" ? 1 : 0` means: if cloud is gcp → count is 1 → create resource. If not → count is 0 → skip.

When `count = 0` or `for_each = {}`, Terraform doesn't create the resource, doesn't even validate its arguments. The module exists in code but produces zero resources.

---

## 6. Region/Zone Dictionary

**Mentor's question:** Why separate `gcp_region`, `gcp_zone`, `aws_region` instead of a structured approach? AWS also has availability zones.

**Before (flat):**

```yaml
general:
  gcp_region: "europe-central2"
  gcp_zone: "europe-central2-a"
  aws_region: "eu-central-1"
```

**After (structured):**

```yaml
general:
  regions:
    gcp:
      region: "europe-central2"
      zone: "europe-central2-a"
    aws:
      region: "eu-central-1"
      zone: "eu-central-1b"
```

Access in modules: `var.config.general.regions.gcp.region` or `var.config.general.regions.aws.zone`.

**Why GCP network gets `region` and AWS network gets `zone`:**

GCP subnets are **regional** resources — they span all zones in a region. AWS subnets are **zonal** — each subnet lives in one specific availability zone. Different cloud architectures, different parameters needed.

---

## 7. The `cloud` Variable — What Depends on It

From a single `cloud: "gcp"` or `cloud: "aws"` in config, the entire infrastructure changes:

| What it controls | GCP example | AWS example |
|---|---|---|
| Resource creation | `count = var.config.general.cloud == "gcp" ? 1 : 0` | `count = var.config.general.cloud == "aws" ? 1 : 0` |
| VM creation | `for_each = var.config.general.cloud == "gcp" ? var.config.vms : {}` | `for_each = var.config.general.cloud == "aws" ? var.config.vms : {}` |
| Machine type | `var.config.sizes[each.value.size].gcp` → `e2-micro` | `var.config.sizes[each.value.size].aws` → `t3.micro` |
| Image | `var.config.general.image.gcp` | `var.config.general.image.aws` |
| Region | `var.config.general.regions.gcp.region` | `var.config.general.regions.aws.region` |

If `cloud != "gcp"`, all GCP modules do nothing — `count = 0`, `for_each = {}`. They exist in code but produce zero resources.

---

## 8. Passing Config vs Individual Variables (Major Refactoring)

**Mentor's feedback:** "You're doing double work. The data is already organized in config — why unpack every variable manually?"

### What is `locals`?

```hcl
locals {
  config  = yamldecode(file("${path.module}/config.yaml"))
  general = local.config.general
}
```

`locals` reads the YAML file once and stores the entire structure. `local.config` contains everything. It's like unpacking a box once and leaving everything on the table — available everywhere in the root module.

### Before (double work)

```hcl
module "gcp_vm" {
  source         = "./modules/gcp_vm"
  cloud          = local.general.cloud          # unpack from config
  vms            = local.config.vms             # unpack from config
  sizes          = local.config.sizes           # unpack from config
  zone           = local.general.regions.gcp.zone  # unpack from config
  image          = local.general.image.gcp      # unpack from config
  default_disk   = local.general.disk_size      # unpack from config
  subnetwork     = module.gcp_network.subnet_id
  ops_user       = local.general.ops_user       # unpack from config
  ssh_port       = local.general.ssh_port       # unpack from config
  ssh_public_key = file("...")
}
```

10 lines. 8 of them just unpack values that already exist in `local.config`.

### After (pass config object)

```hcl
module "gcp_vm" {
  source         = "./modules/gcp_vm"
  config         = local.config
  subnetwork     = module.gcp_network.subnet_id
  ssh_public_key = file("${pathexpand("~")}/.ssh/id_ed25519.pub")
}
```

3 lines. The module reads what it needs: `var.config.general.cloud`, `var.config.vms`, `var.config.sizes`, etc.

### The Rule

- **From config.yaml** → pass as `config = local.config` (one variable)
- **From other modules** → pass individually (subnet IDs, security group IDs, VPC names)
- **From local filesystem** → pass individually (`ssh_public_key`)

### Module variables.tf — before and after

**Before (gcp_vm):**

```hcl
variable "cloud" { type = string }
variable "vms" { type = any }
variable "sizes" { type = any }
variable "zone" { type = string }
variable "image" { type = string }
variable "default_disk" { type = number }
variable "subnetwork" { type = string }
variable "ops_user" { type = string }
variable "ssh_port" { type = string }
variable "ssh_public_key" { type = string }
```

10 variables.

**After:**

```hcl
variable "config" { type = any }
variable "subnetwork" { type = string }
variable "ssh_public_key" { type = string }
```

3 variables. Inside the module: `var.config.general.cloud`, `var.config.general.ops_user`, etc.

### What is a ternary?

`condition ? value_if_true : value_if_false`

```hcl
count = var.config.general.cloud == "gcp" ? 1 : 0
# if cloud is "gcp" → count is 1 → create resource
# if cloud is not "gcp" → count is 0 → skip
```

One-line if/else. Used everywhere in modules for cloud switching.

### What is "operational time"?

The mentor's point: if you include modules for clouds you don't use, and one of those cloud providers changes their API, your `terraform plan` will fail even though you don't use that cloud. Extra modules = extra maintenance burden. However, for this project with two clouds, it's acceptable.

---

## 9. Config File Location

**Mentor's note:** The config file shouldn't be in the same directory as Terraform code. In a real project, config comes from a separate source — a different repo, a secrets manager, or CI/CD pipeline. This simulates separation of data from code.

For now, `config.yaml` lives in the terraform directory for simplicity. Future improvement: move it outside and reference it via a path variable.

---

## Verification — Refactoring is Clean

After all changes, `terraform plan` confirmed:

```
No changes. Your infrastructure matches the configuration.
```

The code structure changed entirely, but the infrastructure result is identical. This is what clean refactoring looks like — internal improvement without affecting the outcome.

---

## Current File Structure

```
Cloud_Multi/
├── docs/
│   └── multicloud_demo.md
└── terraform/
    ├── config.yaml                ← single config for both clouds
    ├── main.tf                    ← clean: config + module calls
    ├── outputs.tf                 ← ternary to pick GCP or AWS outputs
    ├── provider.tf                ← both providers declared
    ├── variables.tf               ← only credentials (secrets)
    ├── terraform.tfvars           ← credentials (not in Git)
    ├── backend.tf                 ← GCS remote state
    └── modules/
        ├── gcp_network/           ← VPC + subnet (count-based)
        ├── gcp_security/          ← 3 firewall rules (count-based)
        ├── gcp_vm/                ← GCP VMs (for_each)
        ├── aws_network/           ← VPC + subnets + IGW + routes (count-based)
        ├── aws_security/          ← 2 security groups (count-based)
        └── aws_vm/                ← AWS EC2 instances (for_each)
```

Each module receives `config = local.config` plus only cross-module outputs (subnet IDs, security group IDs, SSH public key).

---

## Root main.tf — Final Version

```hcl
locals {
  config  = yamldecode(file("${path.module}/config.yaml"))
  general = local.config.general
}

module "gcp_network" {
  source = "./modules/gcp_network"
  config = local.config
}

module "gcp_security" {
  source   = "./modules/gcp_security"
  config   = local.config
  vpc_name = module.gcp_network.vpc_name
}

module "gcp_vm" {
  source         = "./modules/gcp_vm"
  config         = local.config
  subnetwork     = module.gcp_network.subnet_id
  ssh_public_key = file("${pathexpand("~")}/.ssh/id_ed25519.pub")
}

module "aws_network" {
  source = "./modules/aws_network"
  config = local.config
}

module "aws_security" {
  source = "./modules/aws_security"
  config = local.config
  vpc_id = module.aws_network.vpc_id
}

module "aws_vm" {
  source            = "./modules/aws_vm"
  config            = local.config
  ssh_public_key    = file("${pathexpand("~")}/.ssh/id_ed25519.pub")
  public_subnet_id  = module.aws_network.public_subnet_id
  private_subnet_id = module.aws_network.private_subnet_id
  jump_host_sg_id   = module.aws_security.jump_host_sg_id
  internal_sg_id    = module.aws_security.internal_sg_id
}
```

---

## config.yaml — Final Version

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

Switching clouds = change `cloud: "gcp"` to `cloud: "aws"` → `terraform apply`.
