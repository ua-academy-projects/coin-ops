# Task: Terraform VM Module + External YAML Configuration

## What We Have Now (The Problem)

Right now, your `main.tf` has **everything hardcoded in one file**: network, firewall rules, jump host VM, and 3 internal VMs. The jump host and internal VMs are defined as **separate resources** — you can't reuse the VM definition for a different project or add a 5th VM without copy-pasting code.

```
Current main.tf:
├── network resource        (hardcoded)
├── subnet resource         (hardcoded)
├── firewall rules          (hardcoded)
├── jump_host VM resource   (unique block, not reusable)
└── internal_vm resource    (count=3, but still hardcoded)
```

**Problems with this approach:**

1. **Not scalable** — if you need 10 VMs with different configs, you'd copy-paste the VM block 10 times
2. **Not reusable** — another project can't use your VM definition without copying the entire file
3. **Configuration mixed with logic** — VM parameters (name, size, tags) are tangled with the resource definition
4. **Hard to change** — updating one parameter means editing `.tf` files, which requires Terraform knowledge

---

## What We Need to Build (The Goal)

Two things:

1. **A Terraform module** — a reusable "template" for creating a VM. You call it with parameters, it creates the VM. One module, many VMs.

2. **An external YAML config file** — all VM definitions live in a YAML file, not in Terraform code. Anyone can edit the YAML without knowing Terraform.

```
New structure:
├── config.yaml              ← VM definitions (data, no logic)
├── main.tf                  ← reads YAML, calls module for each VM
└── modules/
    └── vm/
        ├── main.tf           ← the reusable VM template
        ├── variables.tf      ← what the module accepts (inputs)
        └── outputs.tf        ← what the module returns (outputs)
```

---

## Key Concepts — Definitions You Need to Know

### What is a Terraform Module?

A **module** is a folder containing `.tf` files that acts as a reusable building block. Think of it as a **function** in programming: it takes inputs, does something, and returns outputs.

Without modules, your Terraform code is like one giant `main()` function — everything in one place. With modules, you split it into logical pieces that you can call multiple times with different parameters.

**Every Terraform project is already a module.** Your current `terraform/` folder is called the **root module**. When we create a `modules/vm/` folder — that's a **child module**. The root module calls the child module.

```
root module (terraform/)
    │
    │  module "jump_host" {
    │    source = "./modules/vm"
    │    name   = "jump-host"
    │    ...
    │  }
    │
    ▼
child module (modules/vm/)
    │
    │  resource "google_compute_instance" "vm" {
    │    name = var.name
    │    ...
    │  }
    │
    ▼
GCP creates the VM
```

### Module Interface (Contract)

A module has two boundaries:

**Inputs (`variables.tf`)** — what parameters the module accepts. Like function arguments. The caller must provide these (or they use defaults). Example: VM name, machine type, tags, disk size.

**Outputs (`outputs.tf`)** — what the module returns after creating the resource. Like a function's return value. Example: the VM's IP address, instance ID.

The caller doesn't know **how** the module creates the VM internally. It only knows: "I give it a name and machine type, it gives me back an IP address." This is called **encapsulation** — the internal details are hidden behind the interface.

### Why Not Just Use `count`?

You already use `count = 3` for internal VMs. Why not just change it to `count = 10`?

Because `count` creates **identical** copies. All 3 internal VMs have the same machine type, same tags, same disk size. What if you need one VM with 20GB disk and another with 50GB? Or one with `e2-micro` and another with `e2-medium`? Count can't do that.

A module called with different parameters can create VMs that are **structurally similar** (same resource type) but **differently configured** (different sizes, names, tags, networks).

### What is `for_each`?

`for_each` is Terraform's way to iterate over a collection (a map or a set) and create one resource per item. Unlike `count` (which uses index numbers 0, 1, 2), `for_each` uses **keys** — meaningful names.

```hcl
# count approach — VMs identified by number
resource "vm" "internal_vm" {
  count = 3
  name  = "internal-vm-${count.index + 1}"
  # all identical
}

# for_each approach — VMs identified by name, each with unique config
module "vm" {
  for_each     = var.vms
  source       = "./modules/vm"
  name         = each.key
  machine_type = each.value.machine_type
  tags         = each.value.tags
  # each VM can be different
}
```

With `for_each`, if you remove a VM from the middle of the list, Terraform knows exactly which one to destroy. With `count`, removing item 1 from a list of 3 shifts indexes and causes unexpected recreation of VMs.

### What is a Data Source in Terraform?

In Terraform, there are two main block types:

**`resource`** — creates something new. "I want this to exist."
```hcl
resource "google_compute_instance" "vm" {
  name = "my-vm"  # creates a new VM
}
```

**`data`** — reads something that already exists. "Tell me about this."
```hcl
data "google_compute_image" "ubuntu" {
  family  = "ubuntu-2404-lts-amd64"
  project = "ubuntu-os-cloud"
  # doesn't create anything, just reads info about the latest Ubuntu image
}
```

Your mentor mentioned `data` sources because reading an external YAML file also uses this concept — you're reading external information into Terraform.

### What is External Configuration (YAML)?

Instead of defining VM parameters inside `.tf` files, you define them in a **separate config file** (YAML or JSON). Terraform reads this file and uses the values.

**Why YAML, not just `terraform.tfvars`?**

- `terraform.tfvars` uses HCL syntax — you need to know Terraform's language
- YAML is universal — Ansible, Docker Compose, Kubernetes, CI/CD pipelines all use YAML
- YAML is human-readable — a project manager could edit it
- Same config file could feed both Terraform AND Ansible — one source of truth

**What YAML looks like** (compared to HCL):

```yaml
# YAML — simple, readable
general:
  project_id: "devops-intern-penina"
  region: "europe-central2"
  image: "ubuntu-os-cloud/ubuntu-2404-lts-amd64"

vms:
  jump-host:
    machine_type: "e2-micro"
    tags: ["jump-host"]
    public_ip: true
  internal-vm-1:
    machine_type: "e2-micro"
    tags: ["internal"]
    public_ip: false
```

```hcl
# HCL (terraform.tfvars) — requires Terraform knowledge
vms = {
  "jump-host" = {
    machine_type = "e2-micro"
    tags         = ["jump-host"]
    public_ip    = true
  }
  "internal-vm-1" = {
    machine_type = "e2-micro"
    tags         = ["internal"]
    public_ip    = false
  }
}
```

Both achieve the same result, but YAML is more universal and readable.

### How Terraform Reads YAML

Terraform has a built-in function `yamldecode()` that converts a YAML file into a Terraform data structure:

```hcl
locals {
  config = yamldecode(file("${path.module}/config.yaml"))
}
```

After this, `local.config.general.project_id` returns `"devops-intern-penina"`, and `local.config.vms` returns the map of all VMs. You can then iterate over it with `for_each`.

### What is the Override Pattern?

Your mentor described this: if a VM doesn't specify its own `image`, use the default from the `general` block. But if it does specify one — use the VM-specific value instead.

```yaml
general:
  image: "ubuntu-os-cloud/ubuntu-2404-lts-amd64"   # default for all VMs

vms:
  web-server:
    machine_type: "e2-micro"
    # no image specified → uses general.image (Ubuntu)
  db-server:
    machine_type: "e2-medium"
    image: "debian-cloud/debian-12"   # override → uses Debian instead
```

In Terraform, this is implemented with the `lookup()` function or the `try()` function:

```hcl
image = try(each.value.image, local.config.general.image)
```

Translation: "try to use the VM's own image. If it doesn't exist, fall back to the general image."

This pattern is powerful because it gives you sensible defaults while allowing per-VM customization when needed.

---

## What is Single Responsibility Principle (SRP) in Modules?

From your meeting summary — a module should do **one thing**. Your VM module creates a VM. It doesn't create networks, firewalls, or DNS records. Those would be separate modules.

Your module structure for this task:

| Module | Responsibility |
|---|---|
| `vm` | Creates a single GCP compute instance with given parameters |

The VM module doesn't know about your jump host architecture. It doesn't know about firewalls. It just creates a VM with whatever parameters you give it. The **root module** (`main.tf`) is where you orchestrate — "create this VM with these parameters, that VM with those parameters."

---

## What is Loose Coupling?

**Tight coupling (bad):** Module A directly references the internals of Module B. If Module B changes how it works, Module A breaks.

**Loose coupling (good):** Module A only talks to Module B through its interface (inputs/outputs). Module B can completely rewrite its internals, and Module A doesn't care — as long as the interface stays the same.

In your case: the root module passes `name`, `machine_type`, `tags` to the VM module. The VM module could switch from `google_compute_instance` to a completely different resource type internally — the root module wouldn't need to change.

---

## What is High Cohesion?

Everything inside a module should be **related to the module's purpose**. The VM module should contain everything needed to create a VM (disk, network interface, metadata) — but nothing unrelated (like firewall rules or DNS entries).

If you look inside the VM module and see a firewall rule — that's low cohesion. The firewall has nothing to do with creating a VM. Move it to a firewall module or keep it in the root module.

---

## The Architecture (Design Before Code)

Before writing any Terraform code, here's the design:

```
config.yaml
    │
    │  yamldecode()
    │
    ▼
main.tf (root module)
    │
    │  reads general settings + VM list
    │  iterates with for_each
    │
    ├── module "vm" ["jump-host"]     → modules/vm/ → GCP VM
    ├── module "vm" ["internal-vm-1"] → modules/vm/ → GCP VM
    ├── module "vm" ["internal-vm-2"] → modules/vm/ → GCP VM
    └── module "vm" ["internal-vm-3"] → modules/vm/ → GCP VM
```

**config.yaml** contains:
- `general` block: project-wide defaults (region, image, SSH port, ops user)
- `vms` block: per-VM configuration (name, machine type, tags, public IP, disk size)

**modules/vm/** contains:
- `variables.tf`: what parameters a VM needs (name, type, tags, network, image, etc.)
- `main.tf`: the `google_compute_instance` resource using those variables
- `outputs.tf`: what the module returns (IP addresses, instance ID)

**Root main.tf** contains:
- reads `config.yaml` into a local variable
- still defines network, subnet, firewall rules (not in the module — different responsibility)
- calls the VM module once per VM in the YAML config using `for_each`
- passes each VM's parameters + general defaults with override logic

---

## YAML Config Structure (What You Need to Design)

Think about what parameters each VM needs. Based on your current `main.tf`:

```yaml
general:
  project_id: "devops-intern-penina"
  region: "europe-central2"
  zone: "europe-central2-a"
  image: "ubuntu-os-cloud/ubuntu-2404-lts-amd64"
  machine_type: "e2-micro"
  ssh_port: "9922"
  ops_user: "marta_ops"
  ssh_public_key_path: "~/.ssh/id_ed25519.pub"

vms:
  jump-host:
    tags: ["jump-host"]
    public_ip: true
  internal-vm-1:
    tags: ["internal"]
    public_ip: false
  internal-vm-2:
    tags: ["internal"]
    public_ip: false
  internal-vm-3:
    tags: ["internal"]
    public_ip: false
```

Notice: most VMs use the general defaults (machine_type, image). Only tags and public_ip differ. If later you need one VM with more resources:

```yaml
  db-server:
    machine_type: "e2-medium"     # override — bigger than default
    disk_size: 50                  # override — more storage
    tags: ["internal", "database"]
    public_ip: false
```

---

## VM Module Interface (Inputs & Outputs)

### Inputs (what the module accepts)

| Variable | Type | Required | Description |
|---|---|---|---|
| `name` | string | yes | VM name (e.g., "jump-host") |
| `machine_type` | string | yes | GCP machine type (e.g., "e2-micro") |
| `zone` | string | yes | GCP zone |
| `image` | string | yes | Boot disk image |
| `tags` | list(string) | yes | Network tags for firewall rules |
| `subnetwork` | string | yes | Subnet ID to attach the VM to |
| `public_ip` | bool | no (default: false) | Whether to assign an external IP |
| `disk_size` | number | no (default: 10) | Boot disk size in GB |
| `ssh_user` | string | yes | Operational user name |
| `ssh_public_key` | string | yes | SSH public key content |
| `ssh_port` | string | yes | Custom SSH port |
| `startup_script` | string | no (default: "") | Script to run on first boot |

### Outputs (what the module returns)

| Output | Description |
|---|---|
| `internal_ip` | VM's internal IP address |
| `external_ip` | VM's external IP (null if no public IP) |
| `name` | VM name |
| `instance_id` | GCP instance ID |

---

## Step-by-Step Plan

### Step 1 — Design the YAML config structure
Define what goes in `general` and what goes per-VM. Think about what can be overridden.

### Step 2 — Create the VM module
Write `modules/vm/variables.tf`, `modules/vm/main.tf`, `modules/vm/outputs.tf`. The module creates ONE VM based on the variables it receives.

### Step 3 — Refactor root main.tf
Read the YAML config, iterate over VMs with `for_each`, call the VM module for each. Keep network, subnet, and firewall rules in the root module (different responsibility).

### Step 4 — Implement override logic
Use `try()` or `lookup()` to fall back from VM-specific values to general defaults.

### Step 5 — Test
Run `terraform plan` to see that the same 4 VMs would be created. The result should be identical to what you have now — but the code is modular and scalable.

---

## What NOT to Do (From the Meeting)

1. **Don't start coding immediately** — design first, code second
2. **Don't create a "God Module"** — one module that creates VMs, networks, firewalls, and DNS all at once
3. **Don't hardcode values in the module** — everything comes through variables
4. **Don't copy-paste VM blocks** — use `for_each` to iterate over the YAML config
5. **Don't mix data and logic** — VM parameters belong in YAML, resource definitions belong in `.tf` files

---

## New File Structure (Target)

```
Cloud_GCP/
├── terraform/
│   ├── config.yaml            ← NEW: all VM definitions
│   ├── main.tf                ← REFACTORED: reads YAML, calls module
│   ├── modules/
│   │   └── vm/
│   │       ├── main.tf        ← NEW: reusable VM resource
│   │       ├── variables.tf   ← NEW: module inputs
│   │       └── outputs.tf     ← NEW: module outputs
│   ├── outputs.tf             ← UPDATED: collects outputs from modules
│   ├── variables.tf           ← SIMPLIFIED: fewer variables (most move to YAML)
│   ├── terraform.tfvars       ← SIMPLIFIED: only secrets/paths
│   ├── backend.tf             ← unchanged
│   └── provider.tf            ← unchanged
├── bootstrap.sh
└── docs/
    └── 05-terraform-modules-yaml-config.md  ← this doc
```
