# Terraform & Infrastructure Guide

An educational walkthrough of how we provision and configure the coin-ops Hyper-V cluster using Terraform, cloud-init, and Ansible. Written for DevOps interns who have never touched Terraform or Hyper-V before.

This guide is a companion to `docs/infrastructure-guide.md`, which covers the system architecture, service topology, and Ansible playbooks in depth. Read that first if you haven't. This guide focuses on the *provisioning layer*: how the VMs come to exist in the first place, and how they get from a blank disk image to a running system.

---

## 1. Why We Replaced Vagrant with Terraform

If you look at the git history, you'll find traces of a previous Vagrantfile. Vagrant was doing roughly this: wrapping PowerShell Hyper-V cmdlets (`New-VM`, `Set-VMMemory`, `Start-VM`) inside a Ruby interpreter, triggered by `vagrant up`. It worked — in the sense that it produced running VMs — but it had three serious problems.

**No readable state.** Vagrant tracks what it created by writing a small `.vagrant/` directory with machine IDs. That state is opaque — it's UUIDs and internal references, not a human-readable description of the infrastructure. If you lose the `.vagrant/` directory, Vagrant doesn't know which VMs it owns. You end up SSHing into Hyper-V Manager trying to figure out which of the eight VMs listed are "yours".

**No preview of changes.** Running `vagrant up` when a VM already exists does something different than when it doesn't. There's no way to ask "what would change if I run this?" before committing. You learn what happened by watching it happen.

**Opaque VM lifecycle.** Vagrant's `--provision` flag, `reload`, `destroy --graceful` — these map poorly to the actual Hyper-V state machine. VMs can end up in saved states that Vagrant handles unexpectedly. The tool is an abstraction that leaks in uncomfortable ways.

Terraform solves all three problems.

With Terraform, the configuration in `terraform/*.tf` *is* the documentation. When you read `terraform/vms.tf`, you see exactly what VMs exist, what their memory and CPU are, which switch they're attached to, and which disk image they boot from. There is no gap between the docs and the truth — because the config *is* the truth.

`terraform plan` shows you, before anything changes, exactly what would be created, modified, or destroyed. A plan is a diff between your configuration and the current state. Running `apply` without reviewing `plan` first is like merging a PR you haven't read.

`terraform.tfstate` is the state file — a JSON record of everything Terraform created. Terraform checks this file to know what already exists and what needs to change. It's the bridge between "what your .tf files declare" and "what's actually running in Hyper-V."

The golden rule of Infrastructure as Code: **the file is the documentation.** Not a README someone forgot to update. Not a colleague's memory. The actual configuration file. If it's not in the .tf file, it either doesn't exist or it's infrastructure debt.

---

## 2. Terraform Concepts from Scratch

Terraform has about a dozen core concepts, but you need to understand six of them to read this codebase comfortably.

### Provider

A **provider** is a plugin that translates Terraform's resource declarations into API calls for a specific infrastructure platform. AWS has a provider. Azure has a provider. Kubernetes has a provider. We use `taliesins/hyperv` — a community provider that talks to Hyper-V via WinRM (covered in section 3).

The provider block lives in `terraform/provider.tf` and tells Terraform both *which* provider to download and *how* to authenticate to it. In our case, authentication means WinRM credentials for the Windows host.

### Resource

A **resource** is a thing you want to exist. It has a *type* (what kind of thing) and a *name* (what you're calling it in your config). The type comes from the provider; the name is yours.

```hcl
resource "hyperv_machine_instance" "node_history" {
  name       = "softserve-node-01"
  generation = 2
  # ...
}
```

Here, `hyperv_machine_instance` is the type and `node_history` is the Terraform-side name. The full identifier is `hyperv_machine_instance.node_history`. You reference this in outputs, `depends_on` chains, and `terraform state` commands.

### Variable

A **variable** is an input to your configuration — like a function argument. Variables let you write generic config and fill in machine-specific or secret values at apply time.

In `terraform/variables.tf` you'll see declarations like:

```hcl
variable "winrm_password" {
  description = "Windows administrator password for WinRM connection"
  type        = string
  sensitive   = true
}
```

The `sensitive = true` flag tells Terraform not to print this value in plan output or logs. You supply variable values in `terraform.tfvars` (which is gitignored — never commit it). Inside the config, you reference them as `var.winrm_password`.

### Output

An **output** is a value Terraform prints after `apply` completes. Useful for communicating results to the next step in your workflow — IP addresses, generated names, connection strings.

Look at `terraform/outputs.tf`: after `terraform apply`, Terraform prints the static IPs for all three nodes and even formats a ready-to-paste Ansible inventory block. This is not magic — it's just a string in the config that Terraform evaluates and displays.

### State File

`terraform.tfstate` is how Terraform remembers what it created. Without it, Terraform doesn't know whether a resource already exists or needs to be created. If you delete the state file and run `terraform apply`, Terraform will try to create everything from scratch — usually failing because the VMs already exist.

The state file is gitignored for two reasons:
1. It contains your WinRM password and SSH keys in plaintext.
2. It's machine-specific — it contains VM IDs that are meaningless on a different Hyper-V host.

Don't check it in. Don't share it over Slack. Treat it like a credential.

### The Three Commands

Every Terraform workflow is some combination of three commands:

**`terraform init`** — Downloads the providers listed in `required_providers`. Run this once after cloning the repo, and again whenever `provider.tf` changes. It creates `.terraform/` and `terraform.lock.hf` (the lock file for provider versions — commit this one).

**`terraform plan`** — Reads your `.tf` files, compares against the state file, and prints a diff: `+` for things to create, `-` for things to destroy, `~` for things to modify. Nothing changes when you run plan. This is your review step. Never skip it.

**`terraform apply`** — Runs plan one more time (you'll see it printed), asks you to confirm, then makes it real. After success, it updates `terraform.tfstate`.

### Idempotency

Running `terraform apply` twice on a system that's already in the desired state does nothing. Resources in state that match the configuration are left alone. Only differences trigger changes. This is what makes Terraform safe to re-run: if something fails halfway through, fix it and re-run — Terraform picks up where things diverged.

The `null_resource` blocks (like `null_resource.clone_node01`) are a partial exception: they run their `local-exec` provisioner every time the resource is created. But once they're in state, they don't re-run unless you `taint` them explicitly.

---

## 3. How the Hyper-V Provider Works

### What WinRM Is

Hyper-V only runs on Windows. Terraform's `local-exec` provisioner can run arbitrary shell commands, but the Hyper-V API itself — creating VMs, attaching disks, configuring network adapters — is a Windows-only operation.

WinRM (Windows Remote Management) is the bridge. Think of it as SSH for Windows: a protocol that lets remote clients authenticate and execute commands on a Windows machine. It runs on port 5985 (plain HTTP) or 5986 (HTTPS). The `taliesins/hyperv` provider uses WinRM to send PowerShell commands to the Windows host.

In our setup, Terraform runs inside WSL (a Linux environment on your Windows machine). WSL can't directly call Hyper-V APIs — it's Linux. But it *can* open a WinRM connection to the Windows host and ask it to make the Hyper-V API calls. That's the whole trick.

### Finding the Windows Host IP from WSL

WSL connects to the Windows host via a virtual network adapter. The host's IP on that adapter is your WinRM target. Get it with:

```bash
ip route show default | awk '{print $3}'
```

This prints the gateway address — which, from inside WSL, is always the Windows host. Do not use `127.0.0.1` or `localhost` in `terraform.tfvars` unless you're running Terraform directly on Windows (not in WSL).

### The `taliesins/hyperv` Provider

The provider can manage two resource types relevant to us:

- **`hyperv_network_switch`** — creates a Hyper-V virtual switch (equivalent to running `New-VMSwitch` in PowerShell).
- **`hyperv_machine_instance`** — creates and configures a VM (equivalent to `New-VM`, `Set-VMMemory`, `Add-VMDvdDrive`, etc.).

Let's read `terraform/provider.tf` line by line:

```hcl
terraform {
  required_version = ">= 1.5"

  required_providers {
    hyperv = {
      source  = "taliesins/hyperv"
      version = "~> 1.0"
    }
  }
}
```

This block tells Terraform to download version 1.x of the `taliesins/hyperv` provider from the public registry. `~> 1.0` means "1.0 or higher, but less than 2.0" — patch and minor updates are fine, but a major version bump requires explicit action.

```hcl
provider "hyperv" {
  user     = var.winrm_user
  password = var.winrm_password
  host     = var.winrm_host
  port     = 5985
  https    = false
  insecure = true
  use_ntlm = true
  timeout  = "30s"
}
```

- `port = 5985` + `https = false` — plain HTTP. Acceptable for WSL-to-localhost connections because the traffic never leaves the machine. If you were connecting to a *remote* Hyper-V host, use port 5986 with `https = true`.
- `use_ntlm = true` — Windows authenticates via NTLM by default. Kerberos is the other option but requires domain membership. NTLM works on standalone workstations.
- `insecure = true` — skips TLS certificate verification. Only acceptable here because we're using plain HTTP anyway (no TLS to verify).
- `timeout = "30s"` — how long to wait for WinRM operations before giving up. Some Hyper-V operations (especially VM start) take longer than you'd expect.

### Enabling WinRM on the Windows Host

The provider won't work if WinRM isn't enabled on Windows. Run this once in an elevated PowerShell window:

```powershell
winrm quickconfig
Enable-PSRemoting -Force
```

See the gotchas section (section 8) for what can go wrong here.

---

## 4. What cloud-init Does

### The Problem It Solves

You downloaded a single Ubuntu 24.04 cloud image from `cloud-images.ubuntu.com`. It's a generic disk image — it doesn't know your hostname, your SSH key, or your static IP. You want three VMs from that one image, each with different identities.

The naive solution is: boot the image, SSH in, manually set the hostname, add your SSH key, configure networking. Do this three times. Now do it again when you rebuild.

cloud-init is the automated version of that manual process. It's Ubuntu's "first boot" configuration system — a set of scripts that run once, the very first time a VM starts, to configure the system from a data source. After the first boot, cloud-init marks itself as "already ran" and skips subsequent boots.

### The Three Files

For each node, we have three files in `terraform/cloud-init/node-01/`:

**`meta-data`** — the VM's identity. Cloud-init needs at minimum an `instance-id` (to detect if it's a first boot) and optionally a `local-hostname`:

```yaml
instance-id: softserve-node-01
local-hostname: softserve-node-01
```

The `instance-id` is how cloud-init decides "is this a first boot?" If the instance ID changes, cloud-init treats it as a new instance and reruns. If it stays the same across reboots, cloud-init knows it already ran and stays quiet.

**`user-data`** — what to configure. This is the main configuration file. Its format is YAML, and the first line must be `#cloud-config`:

```yaml
#cloud-config
users:
  - name: vagrant
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    lock_passwd: true
    ssh_authorized_keys:
      - REPLACE_WITH_SSH_KEY
```

Notice `REPLACE_WITH_SSH_KEY` — that's a placeholder. Before Terraform creates the seed ISO, the `null_resource.seed_node01` runs a `sed` command:

```bash
sed -i "s|REPLACE_WITH_SSH_KEY|${var.ssh_public_key}|g" \
  "${var.seed_staging_wsl_path}/node-01/user-data"
```

This replaces the placeholder with your actual public key from `terraform.tfvars`. The substitution happens on the WSL filesystem before `genisoimage` bundles the file into the ISO. The VM never sees the placeholder.

**`network-config`** — the static IP configuration. Cloud-init hands this to Netplan, which configures the network adapter:

```yaml
version: 2
ethernets:
  eth0:
    dhcp4: false
    addresses:
      - 172.31.1.10/24
    routes:
      - to: default
        via: 172.31.1.1
    nameservers:
      addresses:
        - 8.8.8.8
        - 1.1.1.1
```

Note the `routes:` syntax with `to: default` and `via:`. An older Netplan syntax used `gateway4: 172.31.1.1` at the same level as `addresses:`. That syntax is deprecated in Ubuntu 24.04 and will generate warnings — or fail outright on some versions. Always use the `routes:` form.

### The Seed ISO

Cloud-init reads its configuration from a "data source". For VMs without a cloud provider (no EC2, no Azure), the standard data source is a virtual CD-ROM labelled `cidata`.

A seed ISO is exactly that: an ISO 9660 disc image containing the three files above, with the volume label set to `cidata`. The VM sees it as a virtual DVD. On first boot, cloud-init looks for a disc labelled `cidata`, reads the files, and runs.

In `terraform/vms.tf`, the `null_resource.seed_node01` creates this ISO using `genisoimage`:

```bash
genisoimage -output "${var.seed_staging_wsl_path}/node-01-seed.iso" \
  -volid cidata -joliet -rock \
  "${var.seed_staging_wsl_path}/node-01/user-data" \
  "${var.seed_staging_wsl_path}/node-01/meta-data" \
  "${var.seed_staging_wsl_path}/node-01/network-config"
```

The `-volid cidata` flag sets the volume label. `-joliet -rock` are filesystem extensions that allow longer filenames — required because cloud-init looks for files named exactly `user-data`, `meta-data`, and `network-config`.

### Why `dvd_drives`, not `hard_disk_drives`

In `terraform/vms.tf`, the seed ISO is attached as a `dvd_drives` block, not a `hard_disk_drives` block:

```hcl
dvd_drives {
  path                = "${var.seed_staging_windows_path}\\node-01-seed.iso"
  controller_number   = 0
  controller_location = 1
}
```

This is not just convention — it's enforced at the hypervisor level. Hyper-V Generation 2 VMs use a virtual SCSI controller with two types of devices: disk drives (`.vhd`, `.vhdx`) and DVD drives (`.iso`). ISO files must be attached as DVD drives. If you put an ISO path in a `hard_disk_drives` block, Hyper-V will refuse to attach it because ISOs are not valid virtual hard disk images.

The OS disk goes in `hard_disk_drives` at controller_location 0. The seed ISO goes in `dvd_drives` at controller_location 1 (on the same controller).

### What Happens on First Boot

Cloud-init runs in stages, in order:

1. **Network stage** — applies `network-config`. The VM gets its static IP. DNS resolvers are set.
2. **Config stage** — processes `user-data`. Creates the `vagrant` user, sets the shell, writes the SSH authorized_keys file, disables password authentication.
3. **Packages stage** — runs `package_update: true`, installs `openssh-server` and `python3` (as listed in the `packages:` block of `user-data`).
4. **Final stage** — runs `runcmd:` commands. In our case: `systemctl enable ssh` and `systemctl start ssh`.

After all stages complete, cloud-init writes a stamp file (`/var/lib/cloud/instance/boot-finished`) and never runs again on this instance ID.

The whole process takes about 90 seconds to 2 minutes, depending on whether `package_update` needs to download packages. If the Internal switch has no internet access (see the note in `terraform/network.tf`), `package_update` will fail — consider setting `package_update: false` if your switch isn't NATted.

---

## 5. The Full Provisioning Sequence

Here is the complete lifecycle from zero to live dashboard. Each step is explained in terms of what actually happens, not just what command to type.

```
Step 1: terraform init
Step 2: terraform plan
Step 3: terraform apply
Step 4: cloud-init runs on all three VMs (automatic, no command)
Step 5: wait ~2 minutes
Step 6: ansible-playbook provision.yml
Step 7: ansible-playbook deploy.yml
Step 8: open browser at http://172.31.1.12
```

**Step 1 — `terraform init`**

Terraform reads `terraform/provider.tf`, sees `taliesins/hyperv ~> 1.0`, and downloads the provider binary from the Terraform registry into `.terraform/providers/`. It also creates `.terraform.lock.hcl` (commit this — it pins the exact provider version). After init, Terraform can parse and validate your configuration.

**Step 2 — `terraform plan`**

Terraform reads all `*.tf` files, evaluates variable references (prompting for any not in `terraform.tfvars`), and compares the declared resources against `terraform.tfstate`. Since there's no state yet, everything shows as `+` (to be created). You'll see: 1 network switch, 6 `null_resource` blocks (3 VHD clone ops + 3 ISO creation ops), and 3 VM instances. Review the plan. Confirm the paths look correct.

**Step 3 — `terraform apply`**

Terraform asks for confirmation, then works through the dependency graph:

1. Creates `hyperv_network_switch.internal` via WinRM — runs `New-VMSwitch` on Windows.
2. Runs `null_resource.clone_node01/02/03` (PowerShell via WinRM) — copies the base VHD three times, one per VM directory.
3. Runs `null_resource.seed_node01/02/03` (bash in WSL) — copies cloud-init files, substitutes the SSH key, runs `genisoimage` to create the ISOs.
4. Creates the three `hyperv_machine_instance` resources — Terraform issues PowerShell commands to Hyper-V to create and start the VMs.

The `depends_on` blocks in `vms.tf` enforce order: Terraform won't try to create `node_history` until both `clone_node01` and `seed_node01` complete. Without these, Terraform might race ahead and try to attach a disk or ISO that doesn't exist yet.

**Step 4 — cloud-init runs**

The VMs boot. Hyper-V starts them automatically after creation. On the very first boot, cloud-init detects the `cidata` disc, reads the three config files, and runs through its stages: network → users → packages → runcmd. This happens without any human input.

**Step 5 — wait ~2 minutes**

There's no Terraform resource that "waits for cloud-init to finish" — we don't have one because adding it would require polling SSH, which adds complexity. The `terraform/outputs.tf` `next_steps` output tells you to wait 2 minutes and then test SSH:

```bash
ssh vagrant@172.31.1.10
```

If SSH connects and you get a prompt, cloud-init is done. If connection is refused, wait 30 more seconds and retry.

**Step 6 — `ansible-playbook provision.yml`**

Ansible SSHes into all three VMs using the `vagrant` user (key-based auth, no password). It installs system packages: PostgreSQL and RabbitMQ on node-01, Go and Redis on node-02, nginx on node-03. It also creates the `cognitor` database user, the RabbitMQ user, and the database. This step is slow — apt downloads packages. Re-running it is safe (idempotent).

**Step 7 — `ansible-playbook deploy.yml`**

This playbook has four plays:
1. Deploy the Go proxy service to node-02.
2. Deploy the history consumer and API to node-01.
3. Build the React UI locally (on the control node, in your WSL environment).
4. Sync the built `dist/` to node-03 and configure nginx.

The UI build step runs locally because node-03 has no Node.js — it's a minimal nginx server. The build output is static files that don't need Node.js to run.

**Step 8 — browser**

Open `http://172.31.1.12`. nginx on node-03 serves the React bundle. The browser fetches live data from the proxy at `172.31.1.11:8080` and historical data from the API at `172.31.1.10:8000` — both URLs were baked into the bundle at build time.

---

## 6. The React Build Pipeline

### Why There's a Build Step at All

The UI is written in TypeScript + React (`ui-react/`). Browsers cannot execute `.tsx` files directly. They understand HTML, CSS, and plain JavaScript — nothing more. The build step is a translation: TypeScript → JavaScript, JSX → function calls, many source files → a small number of optimized bundles.

Vite is the build tool (`ui-react/vite.config.ts`). It does three things: transpiles TypeScript to JavaScript, bundles all the imports into a handful of output files, and optimizes the output (tree-shaking dead code, minification). The output lands in `ui-react/dist/` — plain HTML, CSS, and JS files that any web server can serve.

### `VITE_PROXY_URL` and `VITE_HISTORY_URL`

The React app needs to know where the proxy and history APIs live. But in production, node-03 is just serving static files — there's no server-side code that can inject configuration at request time.

Vite solves this with build-time environment variables. Any environment variable prefixed with `VITE_` is substituted into the bundle at build time, accessible via `import.meta.env.VITE_*`. The `deploy.yml` play sets them:

```yaml
- name: Build React app
  command: npm run build
  args:
    chdir: "{{ playbook_dir }}/../ui-react"
  environment:
    VITE_PROXY_URL: "http://172.31.1.11:8080"
    VITE_HISTORY_URL: "http://172.31.1.10:8000"
```

After build, the string `http://172.31.1.11:8080` is literally present in the JS bundle. The deployed static files contain hardcoded IPs. For a public SaaS this would be a problem — but for an internal tool with fixed IP addresses, it's the simplest correct approach.

### Why `npm ci` Not `npm install`

`npm install` resolves dependencies and may update `package-lock.json`. `npm ci` strictly installs from the lockfile and fails if there's any discrepancy. This makes builds reproducible: the same lockfile always produces the same `node_modules`. On a CI machine or Ansible-managed control node, you want reproducibility, not "let me resolve the latest compatible version."

### Why We Build on the Control Node, Not node-03

Node-03's job is to serve static files with nginx. It doesn't have Node.js, npm, or any build tooling installed — and it shouldn't. Installing a full Node.js build environment on a production web server adds attack surface (more packages = more CVEs), consumes RAM, and takes time to provision.

The React build runs as a `localhost` play in `ansible/deploy.yml`:

```yaml
- name: Build React UI (local)
  hosts: localhost
  connection: local
  tasks:
    - name: Install npm dependencies
      command: npm ci
      args:
        chdir: "{{ playbook_dir }}/../ui-react"
```

`hosts: localhost` + `connection: local` means this play runs on the control node (your WSL machine), not over SSH to any VM.

### Why `delegate_to: localhost` on the `synchronize` Task

After the build, the `ui` role in `ansible/roles/ui/tasks/main.yml` syncs the `dist/` directory to node-03:

```yaml
- name: Sync React dist/ to web root
  synchronize:
    src: "{{ playbook_dir }}/../ui-react/dist/"
    dest: /var/www/coin-ops/
    delete: yes
    recursive: yes
  delegate_to: localhost
```

The `synchronize` module uses `rsync` under the hood. Without `delegate_to: localhost`, Ansible would try to run rsync *on node-03* and pull files from somewhere — which doesn't work because node-03 doesn't have the `dist/` directory.

`delegate_to: localhost` tells Ansible: "run this task from the control node, but treat the target host as the rsync destination." The result is rsync running on your WSL machine, pushing `dist/` to node-03 over SSH. That's the direction you want: control node pushes, remote node receives.

This is a subtle but common gotcha with `synchronize`. If you see rsync errors about missing source files when deploying to a remote host, check whether `delegate_to: localhost` is present.

---

## 7. Operational Runbook

### Provisioning a Fresh Environment

```bash
# 1. Enter the terraform directory
cd /home/yourname/coin-ops/terraform

# 2. Copy the example vars file and fill in your values
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars:
#   winrm_user / winrm_password — your Windows login
#   winrm_host — output of: ip route show default | awk '{print $3}'
#   base_vhd_path — where you put the downloaded Ubuntu cloud image
#   ssh_public_key — contents of your ~/.ssh/id_rsa.pub

# 3. Download the provider
terraform init

# 4. Review what will be created — do not skip this
terraform plan

# 5. Create the infrastructure
terraform apply

# 6. Wait for cloud-init (approximately 2 minutes)
# Test when ready:
ssh vagrant@172.31.1.10 echo "node-01 ready"
ssh vagrant@172.31.1.11 echo "node-02 ready"
ssh vagrant@172.31.1.12 echo "node-03 ready"

# 7. Install system packages on all VMs
ansible-playbook -i ansible/inventory ansible/provision.yml

# 8. Deploy all services and the UI
ansible-playbook -i ansible/inventory ansible/deploy.yml
```

### Rebuilding and Redeploying the UI Only

After a UI code change, you don't need to reprovision VMs. Just redeploy:

```bash
ansible-playbook -i ansible/inventory ansible/deploy.yml
```

The deploy playbook is idempotent. Running it in full is safe and fast — the proxy and history plays will no-op if nothing changed. The UI build always runs (npm ci + vite build) and the dist/ sync will only update changed files.

If you want to build the UI manually and check the output before deploying:

```bash
cd ui-react
npm ci
VITE_PROXY_URL=http://172.31.1.11:8080 VITE_HISTORY_URL=http://172.31.1.10:8000 npm run build
ls dist/   # should contain index.html and assets/
```

### Destroying and Recreating a Single VM

If node-02 (the proxy VM) is in a bad state and you want to nuke it and start fresh:

```bash
# Destroy just the proxy VM (Terraform leaves the other two untouched)
terraform destroy -target hyperv_machine_instance.node_proxy

# Also destroy the null_resources for node-02 so they re-run on apply
terraform destroy -target null_resource.clone_node02
terraform destroy -target null_resource.seed_node02

# Recreate it
terraform apply

# Wait for cloud-init on node-02
ssh vagrant@172.31.1.11 echo "ready"

# Re-provision and re-deploy just that node
ansible-playbook -i ansible/inventory ansible/provision.yml --limit proxy
ansible-playbook -i ansible/inventory ansible/deploy.yml --limit proxy
```

The `--limit proxy` flag restricts the playbook to hosts in the `[proxy]` group (node-02 only). The history and UI nodes are untouched.

### Checking What Terraform Manages

```bash
# List all resources in state
terraform state list

# Inspect a specific resource (shows all attributes Terraform knows)
terraform state show hyperv_machine_instance.node_history

# Show current state of the network switch
terraform state show hyperv_network_switch.internal
```

`terraform state list` is your first debugging step when something seems off between what the config says and what Hyper-V shows. If a resource is in state but missing from Hyper-V, `terraform apply` will recreate it. If a resource exists in Hyper-V but not in state, Terraform doesn't know about it — use `terraform import` to bring it under management.

---

## 8. Common Gotchas

### 1. WinRM Not Enabled

Symptom: `terraform apply` fails immediately with a connection refused or authentication error.

Fix: Run this in an elevated PowerShell window on the Windows host:

```powershell
winrm quickconfig
Enable-PSRemoting -Force
Set-Item WSMan:\localhost\Client\TrustedHosts -Value "*" -Force
```

The last line is needed when connecting from WSL over the virtual network adapter (WSL is not on the same domain as Windows, so Windows's TrustedHosts whitelist blocks it by default). `"*"` is permissive — for a tighter setting, use the WSL gateway IP specifically.

### 2. Wrong Windows Host IP

Symptom: WinRM connection times out. `terraform plan` hangs.

The `winrm_host` in `terraform.tfvars` must be the Windows host's IP as seen from WSL — not `localhost`, not `127.0.0.1`. Get the correct value:

```bash
ip route show default | awk '{print $3}'
```

If you used `127.0.0.1`, WSL would try to connect to its own loopback, not the Windows host. WinRM isn't listening there.

### 3. cloud-init Doesn't Run — ISO Not Attached

Symptom: VM boots but never gets its hostname, SSH key, or static IP. You can't SSH in.

The most common cause: the seed ISO wasn't attached. Verify in `terraform/vms.tf` that each VM has a `dvd_drives` block pointing to the correct ISO path — not a `hard_disk_drives` block. If you accidentally put an ISO in `hard_disk_drives`, Hyper-V silently skips it.

Also confirm the ISO path uses the Windows path format (`${var.seed_staging_windows_path}\\node-01-seed.iso`), not the WSL path. Hyper-V reads ISO paths from the Windows filesystem, not from WSL's `/mnt/` view of it.

### 4. VM Boots but Has No Network

Symptom: cloud-init runs, SSH key is set, but you can't reach the VM at its expected static IP.

Check the `network-config` file for the node. The Netplan `routes:` format must be:

```yaml
routes:
  - to: default
    via: 172.31.1.1
```

Not the deprecated `gateway4: 172.31.1.1` syntax. Also verify the Internal switch has internet access if `package_update: true` — an Internal switch with no NAT cannot reach apt repositories. Check the comment at the top of `terraform/network.tf` for options.

### 5. Hyper-V Generation 1 vs Generation 2

Our config uses `generation = 2` for all VMs. Generation 2 is UEFI-based and required by the Ubuntu 24.04 cloud image — the cloud image is packaged expecting a UEFI firmware environment and will not boot on a Gen 1 (BIOS) VM.

Do not change `generation = 2` to `generation = 1`. If you're adapting this config for a different OS image that's BIOS-only, you would also need to adjust the controller types and possibly the boot order.

### 6. Secure Boot Blocks Ubuntu

Symptom: Gen 2 VM is created, starts, then immediately shuts down. No output in the VM console.

Hyper-V Gen 2 VMs have Secure Boot enabled by default with the "Microsoft Windows" certificate template, which rejects non-Windows bootloaders. Ubuntu requires the "Microsoft UEFI Certificate Authority" template.

Fix: In Hyper-V Manager, open the VM settings → Security → Secure Boot → change the template to "Microsoft UEFI Certificate Authority". Or disable Secure Boot entirely (less secure but simpler for a local dev environment).

Alternatively, add Secure Boot configuration to the `hyperv_machine_instance` resource if the provider version supports it.

### 7. `genisoimage` Not Found

Symptom: `null_resource.seed_node01` fails with `genisoimage: command not found`.

Install it in WSL:

```bash
sudo apt install genisoimage
```

`genisoimage` is part of the `genisoimage` package on Ubuntu/Debian. It's not installed by default. This is a one-time setup step for your WSL environment.

### 8. State File Lost

Symptom: `terraform.tfstate` is missing or empty. Running `terraform plan` shows everything as "to create" even though the VMs already exist.

You have two options:

**Option A — Import.** If you know the Hyper-V VM names, you can reconstruct state:

```bash
terraform import hyperv_machine_instance.node_history softserve-node-01
terraform import hyperv_machine_instance.node_proxy softserve-node-02
terraform import hyperv_machine_instance.node_ui softserve-node-03
```

This is tedious and doesn't cover `null_resource` blocks (which can't be imported). After importing, you'll still need to `taint` the null_resources if you want them to re-run.

**Option B — Destroy manually and re-apply.** Delete the VMs in Hyper-V Manager, delete the VHD directories from Windows Explorer, delete the ISOs, then run `terraform apply` fresh. This is the clean path when Option A is too painful.

Prevention: keep a backup of `terraform.tfstate` outside the repository (a shared drive, a password manager attachment, anywhere). Losing state is a recoverable problem, but it costs an hour.

### 9. React Build Succeeds but Page Is Blank

Symptom: `ansible-playbook deploy.yml` completes without errors, `http://172.31.1.12` loads, but the dashboard shows nothing. Browser console shows CORS errors.

The Go proxy's CORS configuration allows requests from `http://172.31.1.12` by default (the expected UI origin). If you're accessing the dashboard from a different IP or hostname, the browser's CORS preflight check fails and all API requests are blocked.

Fix: update the proxy's CORS allowed origins to include your actual access URL. The relevant config is in the Go proxy source — look for the CORS middleware configuration in the proxy service code.

This only affects browser-to-proxy communication. `curl` and other non-browser clients are unaffected by CORS.

---

## Closing Thought

Terraform, cloud-init, and Ansible together implement a principle that's easy to state and hard to live by: **nothing should require manual steps that can't be reproduced from a config file.**

When the config files are the source of truth, rebuilding is easy. When they're not, rebuilding requires archaeology — reverse-engineering a system from its current state to figure out how it got that way. That archaeology happens at the worst possible time: during an outage, on a deadline, when the person who set it up originally has left.

The terraform files in this repo are worth studying not for the Hyper-V-specific syntax, but for the pattern: declare what you want, let the tool figure out how to get there, record the result in state. That pattern works whether the target is Hyper-V, AWS, Kubernetes, or something that doesn't exist yet.
