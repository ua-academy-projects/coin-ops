# Terraform VM Module + External YAML Configuration

## Task

Refactor the GCP infrastructure to use:
1. **A reusable Terraform module** for creating VMs — one module, called with different parameters for each VM
2. **An external YAML config file** — VM definitions separated from Terraform code
3. **Override pattern** — general defaults with per-VM overrides

---

## Why This Refactoring?

### The Problem (Before)

```hcl
# Two separate resource blocks — 90% identical code
resource "google_compute_instance" "jump_host" { ... }
resource "google_compute_instance" "internal_vm" { count = 3 ... }
```

- **Not scalable** — adding a VM means copy-pasting 20 lines of Terraform code
- **Not reusable** — another project can't use this VM definition
- **Config mixed with logic** — VM parameters tangled with resource definitions
- **Bug fixing in multiple places** — fix the startup script in one block, forget the other

### The Solution (After)

```
config.yaml          → defines WHAT VMs to create (data)
modules/vm/          → defines HOW to create a VM (logic)
main.tf              → connects them with for_each
```

- Add a VM = 4 lines in YAML, zero Terraform changes
- Fix a bug = one change in the module, all VMs get the fix
- Different project = same module, different YAML

---

## Key Concepts

### Terraform Module

A **folder** containing `.tf` files that acts as a reusable building block. Like a function: takes inputs, creates resources, returns outputs. The folder boundary isolates the module's code from everything else.

```
modules/vm/           ← this FOLDER is the module
├── main.tf           ← resource definition
├── variables.tf      ← inputs (function arguments)
└── outputs.tf        ← outputs (return values)
```

### Root Module vs Child Module

Every Terraform project is already a module — the **root module**. The `modules/vm/` folder is a **child module**. The root module calls child modules.

### for_each vs count

`count = 3` creates 3 **identical** copies identified by index (0, 1, 2). Removing item 1 shifts all indexes — causes unexpected recreation.

`for_each` creates resources from a **map**, identified by name. Each can have unique configuration. Removing one doesn't affect others.

```hcl
# for_each — each VM identified by name, each uniquely configured
module "vm" {
  for_each = local.config.vms    # map from YAML
  source   = "./modules/vm"
  name     = each.key            # "jump-host", "internal-vm-1", etc.
  tags     = each.value.tags     # each VM's own tags
}
```

### External YAML Configuration

VM definitions live in YAML, not in `.tf` files. YAML is universal (Ansible, Docker Compose, Kubernetes all use it), human-readable, and editable without Terraform knowledge.

Terraform reads YAML with `yamldecode(file("config.yaml"))`.

### Override Pattern

General defaults apply to all VMs. Per-VM values override the defaults when specified.

```yaml
general:
  machine_type: "e2-micro"       # default for everyone

vms:
  jump-host:
    tags: ["jump-host"]
    # no machine_type → uses e2-micro from general
  db-server:
    machine_type: "e2-medium"    # override → only this VM is bigger
```

In Terraform: `try(each.value.machine_type, local.general.machine_type)` — try VM-specific first, fall back to general.

### Dynamic Block

Controls whether a Terraform block appears at all. Used for `access_config` (public IP):

```hcl
dynamic "access_config" {
  for_each = var.public_ip ? [1] : []
  content {}
}
```

If `public_ip = true` → list has one item → block appears → VM gets public IP.
If `public_ip = false` → empty list → block absent → no public IP.

### Single Responsibility

The VM module creates ONE VM. It doesn't create networks, firewalls, or DNS. Those stay in the root module. The module doesn't know about jump hosts or internal VMs — it just builds whatever parameters it receives.

**Root module** = architect (decides what to build and where).
**VM module** = builder (knows how to build one building).

### locals

Variables computed inside Terraform, not passed from outside. Used to read and parse the YAML config:

```hcl
locals {
  config  = yamldecode(file("${path.module}/config.yaml"))
  general = local.config.general
}
```

---

## File Structure

```
Cloud_GCP/terraform/
├── config.yaml            ← VM definitions (data, no logic)
├── main.tf                ← reads YAML, network, firewall, calls module
├── modules/
│   └── vm/
│       ├── main.tf        ← reusable VM resource
│       ├── variables.tf   ← module inputs
│       └── outputs.tf     ← module outputs
├── outputs.tf             ← root outputs (IPs, SSH command)
├── variables.tf           ← only credentials_file (secrets stay here)
├── terraform.tfvars       ← only credentials path (not in Git)
├── backend.tf             ← unchanged
└── provider.tf            ← uses local.general instead of variables
```

---

## Implementation

### config.yaml

```yaml
general:
  project_id: "devops-intern-penina"
  region: "europe-central2"
  zone: "europe-central2-a"
  machine_type: "e2-micro"
  image: "ubuntu-os-cloud/ubuntu-2404-lts-amd64"
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

Adding a new VM = add 4 lines under `vms`. No Terraform code changes needed.

### modules/vm/variables.tf

```hcl
variable "name" {
  description = "VM instance name"
  type        = string
}

variable "machine_type" {
  description = "GCP machine type (e.g., e2-micro, e2-medium)"
  type        = string
}

variable "zone" {
  description = "GCP zone where the VM will be created"
  type        = string
}

variable "image" {
  description = "Boot disk image"
  type        = string
}

variable "disk_size" {
  description = "Boot disk size in GB"
  type        = number
  default     = 10
}

variable "tags" {
  description = "Network tags for firewall rules"
  type        = list(string)
}

variable "subnetwork" {
  description = "Subnetwork ID to attach the VM to"
  type        = string
}

variable "public_ip" {
  description = "Whether to assign an external IP"
  type        = bool
  default     = false
}

variable "ssh_user" {
  description = "Operational user for SSH access"
  type        = string
}

variable "ssh_public_key" {
  description = "SSH public key content"
  type        = string
}

variable "ssh_port" {
  description = "Custom SSH port"
  type        = string
}
```

`subnetwork` is a variable (not created inside the module) because the subnet is a shared resource — one subnet for all VMs. The root module creates it once and passes the ID.

`ssh_public_key` receives the key content (not a file path) because the module doesn't know where the key lives on your machine.

### modules/vm/main.tf

```hcl
resource "google_compute_instance" "vm" {
  name         = var.name
  machine_type = var.machine_type
  zone         = var.zone
  tags         = var.tags

  boot_disk {
    initialize_params {
      image = var.image
      size  = var.disk_size
    }
  }

  network_interface {
    subnetwork = var.subnetwork

    dynamic "access_config" {
      for_each = var.public_ip ? [1] : []
      content {}
    }
  }

  metadata = {
    ssh-keys = "${var.ssh_user}:${var.ssh_public_key}"
  }

  metadata_startup_script = <<-EOT
    #!/bin/bash
    if [ -f /etc/ssh/sshd_config.d/custom-port.conf ]; then
      echo "SSH already configured, skipping"
      exit 0
    fi
    cloud-init status --wait
    systemctl disable --now ssh.socket
    echo "Port ${var.ssh_port}" > /etc/ssh/sshd_config.d/custom-port.conf
    systemctl enable ssh.service
    systemctl restart ssh.service
  EOT
}
```

One resource block handles both jump host and internal VMs. The `dynamic "access_config"` block is the only difference — controlled by `var.public_ip`.

### modules/vm/outputs.tf

```hcl
output "internal_ip" {
  description = "Internal IP address of the VM"
  value       = google_compute_instance.vm.network_interface[0].network_ip
}

output "external_ip" {
  description = "External IP address (null if no public IP)"
  value       = var.public_ip ? google_compute_instance.vm.network_interface[0].access_config[0].nat_ip : null
}

output "name" {
  description = "VM instance name"
  value       = google_compute_instance.vm.name
}

output "instance_id" {
  description = "GCP instance ID"
  value       = google_compute_instance.vm.instance_id
}
```

`network_interface[0]` — the `[0]` means "first item in the list." Terraform stores network interfaces as a list. We have one, so index 0.

`external_ip` uses a ternary: if no public IP, return `null` instead of crashing on missing `access_config[0]`.

### Root main.tf

```hcl
locals {
  config  = yamldecode(file("${path.module}/config.yaml"))
  general = local.config.general
}

# --- Network ---
resource "google_compute_network" "vpc" {
  name                    = "devops-network"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "subnet" {
  name          = "devops-subnet"
  ip_cidr_range = "10.0.1.0/24"
  region        = local.general.region
  network       = google_compute_network.vpc.id
}

# --- Firewall rules ---
resource "google_compute_firewall" "allow_ssh_external" {
  name    = "allow-ssh-external"
  network = google_compute_network.vpc.name
  allow {
    protocol = "tcp"
    ports    = [local.general.ssh_port]
  }
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["jump-host"]
}

resource "google_compute_firewall" "allow_ssh_internal" {
  name    = "allow-ssh-internal"
  network = google_compute_network.vpc.name
  allow {
    protocol = "tcp"
    ports    = [local.general.ssh_port]
  }
  source_tags = ["jump-host"]
  target_tags = ["internal"]
}

resource "google_compute_firewall" "allow_internal" {
  name    = "allow-internal"
  network = google_compute_network.vpc.name
  allow { protocol = "tcp" }
  allow { protocol = "udp" }
  allow { protocol = "icmp" }
  source_tags = ["internal"]
  target_tags = ["internal"]
}

# --- VMs: one module call per VM in config.yaml ---
module "vm" {
  for_each = local.config.vms
  source   = "./modules/vm"

  name         = each.key
  machine_type = try(each.value.machine_type, local.general.machine_type)
  zone         = local.general.zone
  image        = try(each.value.image, local.general.image)
  disk_size    = try(each.value.disk_size, local.general.disk_size)
  tags         = each.value.tags
  public_ip    = each.value.public_ip
  subnetwork   = google_compute_subnetwork.subnet.id
  ssh_user     = local.general.ops_user
  ssh_public_key = file("${pathexpand("~")}/.ssh/id_ed25519.pub")
  ssh_port     = local.general.ssh_port
}
```

Key lines:

- `for_each = local.config.vms` — iterates over the YAML vms map, creates one module instance per VM
- `each.key` — the VM name from YAML (jump-host, internal-vm-1, etc.)
- `try(each.value.machine_type, local.general.machine_type)` — override pattern
- `pathexpand("~")` — cross-platform home directory resolution (works on Windows, Linux, Mac)

### Root variables.tf

```hcl
variable "credentials_file" {
  description = "Path to service account key"
  type        = string
}
```

Only one variable — the secret credential path. Everything else moved to `config.yaml`.

### Root outputs.tf

```hcl
output "jump_host_external_ip" {
  description = "Public IP of the jump host"
  value       = module.vm["jump-host"].external_ip
}

output "jump_host_internal_ip" {
  description = "Internal IP of the jump host"
  value       = module.vm["jump-host"].internal_ip
}

output "internal_vm_ips" {
  description = "Internal IPs of all internal VMs"
  value = {
    for name, vm in module.vm : name => vm.internal_ip
    if name != "jump-host"
  }
}

output "ssh_connection" {
  description = "SSH command to connect to jump host"
  value       = "ssh -p ${local.general.ssh_port} ${local.general.ops_user}@${module.vm["jump-host"].external_ip}"
}
```

`module.vm["jump-host"]` — accesses a specific module instance by its `for_each` key.

`internal_vm_ips` uses a `for` expression with a filter — returns a map of name → IP for all VMs except jump-host.

### provider.tf

```hcl
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  credentials = file(var.credentials_file)
  project     = local.general.project_id
  region      = local.general.region
  zone        = local.general.zone
}
```

Reads project/region/zone from `local.general` (YAML) instead of variables.

### terraform.tfvars

```hcl
credentials_file = "../key.json"
```

Only the secret path. Everything else is in `config.yaml`.

---

## Result

```
Apply complete! Resources: 4 added, 0 changed, 0 destroyed.

Outputs:

internal_vm_ips = {
  "internal-vm-1" = "10.0.1.35"
  "internal-vm-2" = "10.0.1.37"
  "internal-vm-3" = "10.0.1.36"
}
jump_host_external_ip = "34.116.176.239"
jump_host_internal_ip = "10.0.1.38"
ssh_connection = "ssh -p 9922 marta_ops@34.116.176.239"
```

- 4 VMs created through one module with `for_each`
- `internal_vm_ips` is now a **map** (name → IP) instead of a list — you know which IP belongs to which VM
- `ssh_connection` output gives the exact command to connect

---

## Problems Encountered

### 1. `file("~/.ssh/...")` failed on Windows

**Error:** `no file exists at "~/.ssh/id_ed25519.pub"`

**Cause:** Terraform on Windows doesn't expand `~` as home directory. Git Bash does, but Terraform runs as a Windows process.

**Fix:** `pathexpand("~")` — Terraform's cross-platform home directory function:

```hcl
ssh_public_key = file("${pathexpand("~")}/.ssh/id_ed25519.pub")
```

### 2. SSH key saved with garbled filename

**Cause:** Pressing arrow keys during `ssh-keygen` prompt inserted escape codes into the filename.

**Fix:** Use `-f` flag to explicitly set the output path:

```bash
ssh-keygen -t ed25519 -C "marta_ops-gcp" -f /c/Users/ASUS/.ssh/id_ed25519
```

### 3. GCP name conflict during apply

**Error:** `The resource already exists`

**Cause:** Terraform destroyed old VMs and created new ones in parallel. GCP hadn't fully released the VM names.

**Fix:** Run `terraform apply` again after GCP finishes cleanup.

---

## How to Add a New VM

Edit `config.yaml` only:

```yaml
vms:
  # ... existing VMs ...

  monitoring:
    tags:
      - "internal"
    public_ip: false
```

Then `terraform apply`. To override defaults:

```yaml
  db-server:
    machine_type: "e2-medium"    # bigger than default
    disk_size: 50                # more storage
    tags:
      - "internal"
      - "database"
    public_ip: false
```

---

## Key DevOps Lessons

1. **Design before code** — define the YAML structure and module interface before writing Terraform

2. **Single Responsibility** — the VM module only creates VMs. Networks and firewalls stay in the root module

3. **Loose coupling** — the module doesn't know about jump hosts, firewalls, or project architecture. It just creates whatever VM you describe

4. **Data separate from logic** — VM parameters in YAML (data), resource definitions in `.tf` (logic). Different people can edit different files

5. **Override pattern** — general defaults for the 90% case, per-VM overrides for the 10%. Same pattern in Ansible (group_vars/host_vars), Kubernetes (namespace defaults/pod specs), Docker Compose

6. **for_each over count** — named instances instead of numbered indexes. Removing a VM from the middle doesn't affect others

7. **Modules = functions** — inputs (variables.tf), logic (main.tf), outputs (outputs.tf). The caller doesn't need to know the internals

8. **Shared resources stay in root** — subnet, network, firewall rules are shared by all VMs. They belong in the root module, not inside the VM module

9. **Secrets separate from config** — `credentials_file` in `terraform.tfvars` (not in Git), everything else in `config.yaml` (safe for Git)
