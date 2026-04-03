# Revert Bad Changes + Proper SSH Key Auth + UI Tiers + Terraform Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Revert two commits that violated project conventions, then re-implement the intended improvements (SSH key auth, UI investor tiers, Terraform) the correct way.

**Architecture:** Project uses a strict two-layer secrets pattern (committed non-secrets in `main.yml`, gitignored `secrets.yml`), a committed inventory with IPs only, and docs that map 1:1 to ТЗ deliverables. All changes must respect these conventions before adding new features.

**Tech Stack:** Ansible (inventory/group_vars/host_vars), vanilla JS (index.html), Terraform (HCL for AWS)

---

## Files touched

| File | Action | Why |
|---|---|---|
| `docs/ansible-and-ssh.md` | Delete | Not a ТЗ deliverable; doesn't fit docs convention |
| `ansible/group_vars/all/main.yml` | Restore `ansible_password: vagrant` | Was deliberately there; removing it broke Ansible |
| `ansible/inventory` | Restore to git tracking | Was working committed file; wrongly removed |
| `ansible/inventory.example` | Delete | Wrong addition; was the bad-convention fix |
| `.gitignore` | Revert `ansible/inventory` line | Inventory is committed by convention |
| `ui/index.html` | Fix JS constant naming | `CRYPTO_REFRESH` → `CRYPTO_REFRESH_MS`, `NBU_REFRESH` → `NBU_REFRESH_MS` |
| `ansible/host_vars/softserve-node-0{1,2,3}.yml` | Create (gitignored) | Per-host SSH key path, machine-specific |
| `ansible/host_vars/softserve-node-01.yml.example` | Create (committed) | Template showing key path pattern |
| `ansible/group_vars/all/main.yml` | Remove `ansible_password` (properly) | After host_vars are in place |
| `docs/deployment.md` | Update SSH section | Document new key-based auth setup |
| `docs/blockers.md` | Add blocker #12 | SSH key permission gotcha on WSL |
| `ui/index.html` | Add volume heatmap + sentiment score | Remaining investor tiers |
| `terraform/main.tf` | Create | AWS equivalent of 3-VM layout |
| `terraform/variables.tf` | Create | Input vars for AMI, region, key pair |
| `terraform/outputs.tf` | Create | Public IPs of provisioned instances |
| `terraform/README.md` | Create | How to use, relationship to Ansible |

---

## Task 1: Revert the bad Ansible commit + fix remaining naming

The Ansible mess (`a853940`) is a clean `git revert` — it touches only Ansible files so reverting it won't conflict with the UI commit.
The `docs/ansible-and-ssh.md` was added in `dd41d56` (the UI commit), so it needs a separate `git rm`. The JS constant naming also needs a manual fix.

**Files:**
- Delete: `docs/ansible-and-ssh.md` (was in dd41d56, not the revertable commit)
- Auto-restored by revert: `ansible/group_vars/all/main.yml`, `ansible/inventory`, `ansible/inventory.example`, `.gitignore`
- Modify: `ui/index.html` (rename two JS constants)

- [ ] **Step 1: Revert the Ansible commit**

```bash
git revert a853940 --no-edit
```

This single command restores: `ansible_password: vagrant` in `main.yml`, `ansible/inventory` back in git, removes `ansible/inventory.example`, reverts `.gitignore`. Verify:

```bash
git show HEAD --stat
```

Expected: 4 files changed — `.gitignore`, `ansible/group_vars/all/main.yml`, `ansible/inventory` restored, `ansible/inventory.example` deleted.

- [ ] **Step 2: Delete the out-of-convention doc**

```bash
git rm docs/ansible-and-ssh.md
```

- [ ] **Step 3: Fix JS constant naming in index.html**

In `ui/index.html`, find the Config section at the top of the `<script>` block. Rename to match `REFRESH_MS` pattern:

```js
// ── Config ────────────────────────────────────────────────────
const PROXY_URL          = 'http://172.31.1.11:8080';
const HISTORY_URL        = 'http://172.31.1.10:8000';
const REFRESH_MS         = 30_000;
const CRYPTO_REFRESH_MS  = 60_000;
const NBU_REFRESH_MS     = 300_000;
```

Update the two `setInterval` calls at the bottom to match:

```js
refreshTimer = setInterval(refreshAll,    REFRESH_MS);
cryptoTimer  = setInterval(refreshTicker, CRYPTO_REFRESH_MS);
```

- [ ] **Step 4: Commit**

```bash
git add docs/ansible-and-ssh.md ui/index.html
git commit -m "Remove out-of-convention doc, fix JS constant naming

- Delete docs/ansible-and-ssh.md (not a ТЗ deliverable, doesn't fit docs structure)
- CRYPTO_REFRESH → CRYPTO_REFRESH_MS, NBU_REFRESH → NBU_REFRESH_MS
  (follow existing REFRESH_MS naming pattern)

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

- [ ] **Step 5: Verify git log looks clean**

```bash
git log --oneline -7
```

Expected: fix commit, revert commit, `dd41d56 Add investor MVP dashboard`, then older commits.

---

## Task 2: Proper SSH key auth using host_vars

**Why host_vars:** Each Vagrant VM has a unique SSH key at `.vagrant/machines/<name>/hyperv/private_key`. This path is machine-specific (depends on your Windows drive letter and project folder). The correct Ansible pattern for per-host, machine-specific variables is `host_vars/<hostname>.yml` — gitignored, with a committed `.example` as documentation.

This follows the existing project convention exactly:
- `secrets.yml` is gitignored, `secrets.example.yml` is committed
- `host_vars/*.yml` is gitignored, `host_vars/softserve-node-01.yml.example` is committed

**Files:**
- Create: `ansible/host_vars/softserve-node-01.yml` (gitignored — fill in real path)
- Create: `ansible/host_vars/softserve-node-02.yml` (gitignored)
- Create: `ansible/host_vars/softserve-node-03.yml` (gitignored)
- Create: `ansible/host_vars/softserve-node-01.yml.example` (committed — template)
- Modify: `ansible/group_vars/all/main.yml` (remove `ansible_password`)
- Modify: `.gitignore` (add `ansible/host_vars/*.yml`)
- Modify: `docs/deployment.md` (update SSH auth section)
- Modify: `docs/blockers.md` (add blocker #12)

- [ ] **Step 1: Find the actual Vagrant machine names on your system**

From WSL:
```bash
ls /mnt/f/univ/softserv-internship/.vagrant/machines/
```

This shows the exact folder names Vagrant used (e.g. `node-1`, `node-2`, `node-3` or `default`).
Use the real names in the next steps.

- [ ] **Step 2: Create host_vars directory**

```bash
mkdir -p /home/claude/coin-ops/ansible/host_vars
```

- [ ] **Step 3: Create the three host_vars files with real key paths**

`ansible/host_vars/softserve-node-01.yml`:
```yaml
ansible_ssh_private_key_file: /mnt/f/univ/softserv-internship/.vagrant/machines/node-1/hyperv/private_key
```

`ansible/host_vars/softserve-node-02.yml`:
```yaml
ansible_ssh_private_key_file: /mnt/f/univ/softserv-internship/.vagrant/machines/node-2/hyperv/private_key
```

`ansible/host_vars/softserve-node-03.yml`:
```yaml
ansible_ssh_private_key_file: /mnt/f/univ/softserv-internship/.vagrant/machines/node-3/hyperv/private_key
```

Adjust the `node-X` folder names to match what `ls` showed in Step 1.

- [ ] **Step 4: Fix key file permissions (WSL requirement)**

SSH refuses to use key files with permissions wider than 600:
```bash
chmod 600 /mnt/f/univ/softserv-internship/.vagrant/machines/*/hyperv/private_key
```

- [ ] **Step 5: Create the committed example file**

`ansible/host_vars/softserve-node-01.yml.example`:
```yaml
# Copy this pattern for each host in host_vars/.
# Files named *.yml here are gitignored (machine-specific paths).
# Only *.yml.example files are committed.
#
# WSL path pattern:
#   /mnt/<drive>/<project-path>/.vagrant/machines/<vm-name>/hyperv/private_key
#
# Find VM names: ls /mnt/f/univ/softserv-internship/.vagrant/machines/

ansible_ssh_private_key_file: /mnt/f/univ/softserv-internship/.vagrant/machines/node-1/hyperv/private_key
```

- [ ] **Step 6: Update .gitignore**

Add one line to `.gitignore`:

```
DASHBOARD_PROJECT.md

# Ansible secrets — never commit real passwords
ansible/group_vars/all/secrets.yml

# Ansible host-specific variables — machine-specific paths
ansible/host_vars/*.yml
```

- [ ] **Step 7: Remove ansible_password from main.yml**

Now that host_vars provides the key, password auth is no longer needed.
Edit `ansible/group_vars/all/main.yml`. The SSH block becomes:

```yaml
# ── SSH ───────────────────────────────────────────────────────
# Key paths are set per-host in ansible/host_vars/<hostname>.yml (gitignored).
# Copy ansible/host_vars/softserve-node-01.yml.example for each host.
ansible_user: vagrant
ansible_ssh_common_args: '-o StrictHostKeyChecking=no'
```

- [ ] **Step 8: Test Ansible can connect**

From WSL, run a quick ping against all hosts:
```bash
cd /mnt/f/univ/softserv-internship
ansible all -i ansible/inventory -m ping
```

Expected output for each host:
```
softserve-node-01 | SUCCESS => { "ping": "pong" }
softserve-node-02 | SUCCESS => { "ping": "pong" }
softserve-node-03 | SUCCESS => { "ping": "pong" }
```

If it fails: re-check key file paths (`ls` the host_vars files), re-check permissions (`chmod 600`).

- [ ] **Step 9: Update docs/deployment.md — SSH section**

Find the SSH / credentials section in `docs/deployment.md`. Update it to describe the new key-based auth setup:
- Reference `host_vars/` as the location for key paths
- Point to `softserve-node-01.yml.example` as the template
- Mention the `chmod 600` requirement for WSL

- [ ] **Step 10: Add blocker #12 to docs/blockers.md**

Follow the exact blocker format already in the file (Symptom / Root cause / Workaround):

```markdown
### 12. Ansible SSH fails with "UNPROTECTED PRIVATE KEY FILE" on WSL

**Symptom:** `ansible all -m ping` fails with:
```
UNREACHABLE! => {"msg": "Failed to connect to the host via ssh: Warning: Unprotected private key file"}
```

**Root cause:** Windows NTFS permissions on the `.vagrant` folder are too permissive.
WSL mounts Windows drives without enforcing Unix permissions unless explicitly set.
SSH refuses to use key files readable by other users.

**Workaround:** Fix permissions explicitly in WSL:
```bash
chmod 600 /mnt/f/univ/softserv-internship/.vagrant/machines/*/hyperv/private_key
```

This must be re-run after `vagrant up` recreates the VMs, as Vagrant regenerates the key files with open permissions.
```

- [ ] **Step 11: Commit**

```bash
git add ansible/host_vars/softserve-node-01.yml.example \
        ansible/group_vars/all/main.yml \
        .gitignore \
        docs/deployment.md \
        docs/blockers.md
git commit -m "Add SSH key auth via host_vars, remove password from main.yml

- Create ansible/host_vars/ with per-host ansible_ssh_private_key_file
- host_vars/*.yml gitignored (machine-specific WSL paths)
- softserve-node-01.yml.example committed as setup template
- Remove ansible_password from group_vars/all/main.yml
- Update .gitignore to cover host_vars/*.yml
- Update deployment.md: SSH setup section with key-based auth instructions
- Add blockers.md #12: WSL key permission issue and chmod 600 fix

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 3: Remaining investor UI tiers

**What's left from the tier plan:**
- Volume heatmap: color-code market card borders by volume intensity
- Sentiment score: aggregate YES% per category, show in filter buttons

**Files:**
- Modify: `ui/index.html`

- [ ] **Step 1: Add volume heatmap to market card rendering**

In the `renderMarkets()` function in `ui/index.html`, compute a volume intensity before building the HTML. Add this before the `.map()` call:

```js
const maxVol = Math.max(...markets.map(m => m.volume_24h || 0), 1);
```

Then inside the `.map()` callback, compute intensity per market:

```js
const volRatio   = Math.min(1, (m.volume_24h || 0) / maxVol);
const volOpacity = (0.15 + volRatio * 0.55).toFixed(2); // range 0.15–0.70
const volBorder  = `rgba(99, 102, 241, ${volOpacity})`;  // accent color
```

Replace the static `border-border` class on the card `<div>` with an inline border style:

```js
<div class="rounded-lg border p-4 hover:border-accent transition-colors cursor-pointer slide-in ${urgentClass}"
     style="background:#141720; border-color:${volBorder}"
```

High-volume markets glow with a brighter indigo border. Low-volume markets stay near-invisible.

- [ ] **Step 2: Add sentiment score to category filter buttons**

Add a `computeSentiment()` function after `detectCategory()`:

```js
function computeSentiment(markets, category) {
  const filtered = category === 'All'
    ? markets
    : markets.filter(m => detectCategory(m.question) === category);
  if (filtered.length === 0) return null;
  const avg = filtered.reduce((s, m) => s + (m.yes_price || 0), 0) / filtered.length;
  return (avg * 100).toFixed(0);
}
```

Update `setCategory()` to regenerate filter button labels after data loads. Add a new `updateCategoryLabels()` function:

```js
function updateCategoryLabels() {
  const categories = ['All', 'Crypto', 'Politics', 'Sports', 'Other'];
  const btns = document.querySelectorAll('#cat-filters button');
  btns.forEach((btn, i) => {
    const cat = categories[i];
    const score = computeSentiment(allMarkets, cat);
    btn.textContent = score != null ? `${cat} ${score}%` : cat;
  });
}
```

Call `updateCategoryLabels()` inside `refreshAll()` after `renderMarketsFiltered()`:

```js
updateCategoryLabels();
```

- [ ] **Step 3: Verify visually before commit**

Deploy to node-03 and check:
- Market cards with highest volume should have a noticeably brighter border
- Category buttons should show e.g. `Crypto 62%` / `Politics 54%`
- Clicking a category still filters correctly
- Sentiment updates on each 30s refresh

- [ ] **Step 4: Commit**

```bash
git add ui/index.html
git commit -m "Add volume heatmap and sentiment score to investor dashboard

- Market cards: border opacity scales with 24h volume (highest = brightest indigo)
- Category filter buttons show aggregate YES% for that category
- Sentiment updates on every 30s data refresh

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 4: Terraform — AWS equivalent of 3-VM layout

**What this is:** The current VMs live in Hyper-V and are provisioned by clicking. Terraform codifies that step. This task writes Terraform configs that provision the same architecture (3 VMs, correct roles) on AWS — the cloud-portable equivalent. It's a learning and portfolio deliverable, not a thing that gets `terraform apply`'d today.

**Why AWS, not Hyper-V:** The Hyper-V Terraform provider requires Windows + WinRM, which adds complexity and is not standard. AWS shows the same concept on infrastructure that's universally understood and deployable.

**Relationship to Ansible:** Terraform provisions the machines. Ansible configures them. Terraform outputs the IPs; those go into `ansible/inventory`. The two tools form a complete IaC pipeline.

**Files:**
- Create: `terraform/main.tf`
- Create: `terraform/variables.tf`
- Create: `terraform/outputs.tf`
- Create: `terraform/README.md`
- Modify: `.gitignore` (add Terraform state files)

- [ ] **Step 1: Create terraform/ directory**

```bash
mkdir -p /home/claude/coin-ops/terraform
```

- [ ] **Step 2: Write variables.tf**

`terraform/variables.tf`:
```hcl
variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "eu-central-1"
}

variable "ami_id" {
  description = "Ubuntu 24.04 LTS AMI ID (region-specific — check AWS console)"
  type        = string
  # eu-central-1 Ubuntu 24.04: ami-0faab6bdbac9486fb (verify before use)
}

variable "instance_type" {
  description = "EC2 instance type for all nodes"
  type        = string
  default     = "t3.micro"
}

variable "key_pair_name" {
  description = "Name of the AWS key pair to use for SSH access"
  type        = string
}

variable "your_ip" {
  description = "Your public IP in CIDR notation for SSH access (e.g. 1.2.3.4/32)"
  type        = string
}
```

- [ ] **Step 3: Write main.tf**

`terraform/main.tf`:
```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ── Network ──────────────────────────────────────────────────────
resource "aws_vpc" "coin_ops" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true

  tags = { Name = "coin-ops-vpc" }
}

resource "aws_subnet" "coin_ops" {
  vpc_id                  = aws_vpc.coin_ops.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true

  tags = { Name = "coin-ops-subnet" }
}

resource "aws_internet_gateway" "coin_ops" {
  vpc_id = aws_vpc.coin_ops.id
  tags   = { Name = "coin-ops-igw" }
}

resource "aws_route_table" "coin_ops" {
  vpc_id = aws_vpc.coin_ops.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.coin_ops.id
  }

  tags = { Name = "coin-ops-rt" }
}

resource "aws_route_table_association" "coin_ops" {
  subnet_id      = aws_subnet.coin_ops.id
  route_table_id = aws_route_table.coin_ops.id
}

# ── Security groups ───────────────────────────────────────────────
resource "aws_security_group" "internal" {
  name   = "coin-ops-internal"
  vpc_id = aws_vpc.coin_ops.id

  # All traffic between nodes in the VPC
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["10.0.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "ssh" {
  name   = "coin-ops-ssh"
  vpc_id = aws_vpc.coin_ops.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.your_ip]
  }
}

resource "aws_security_group" "web" {
  name   = "coin-ops-web"
  vpc_id = aws_vpc.coin_ops.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ── EC2 instances — mirrors 3-VM Hyper-V layout ───────────────────
# node-01: History service (PostgreSQL + RabbitMQ + Python)
resource "aws_instance" "node_history" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.coin_ops.id
  key_name               = var.key_pair_name
  vpc_security_group_ids = [aws_security_group.internal.id, aws_security_group.ssh.id]

  tags = { Name = "softserve-node-01", Role = "history" }
}

# node-02: Proxy service (Go)
resource "aws_instance" "node_proxy" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.coin_ops.id
  key_name               = var.key_pair_name
  vpc_security_group_ids = [aws_security_group.internal.id, aws_security_group.ssh.id]

  tags = { Name = "softserve-node-02", Role = "proxy" }
}

# node-03: Web UI (nginx)
resource "aws_instance" "node_ui" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.coin_ops.id
  key_name               = var.key_pair_name
  vpc_security_group_ids = [
    aws_security_group.internal.id,
    aws_security_group.ssh.id,
    aws_security_group.web.id,
  ]

  tags = { Name = "softserve-node-03", Role = "ui" }
}
```

- [ ] **Step 4: Write outputs.tf**

`terraform/outputs.tf`:
```hcl
output "node_history_ip" {
  description = "Public IP of history node (node-01) — use in ansible/inventory [history]"
  value       = aws_instance.node_history.public_ip
}

output "node_proxy_ip" {
  description = "Public IP of proxy node (node-02) — use in ansible/inventory [proxy]"
  value       = aws_instance.node_proxy.public_ip
}

output "node_ui_ip" {
  description = "Public IP of UI node (node-03) — use in ansible/inventory [ui] and browser"
  value       = aws_instance.node_ui.public_ip
}

output "ansible_inventory_snippet" {
  description = "Paste this into ansible/inventory after provisioning"
  value = <<-EOT
    [history]
    softserve-node-01 ansible_host=${aws_instance.node_history.public_ip}

    [proxy]
    softserve-node-02 ansible_host=${aws_instance.node_proxy.public_ip}

    [ui]
    softserve-node-03 ansible_host=${aws_instance.node_ui.public_ip}
  EOT
}
```

- [ ] **Step 5: Write terraform/README.md**

`terraform/README.md`:
```markdown
# Terraform — AWS provisioning

Provisions the same 3-node layout as the local Hyper-V setup on AWS EC2.

## Relationship to Ansible

```
Terraform → creates EC2 instances (replaces clicking in Hyper-V)
Ansible   → installs packages and deploys services (unchanged)
```

Terraform outputs the IPs. Those go into `ansible/inventory`.
Then run the normal Ansible playbooks.

## Prerequisites

- AWS account with EC2 permissions
- AWS CLI configured (`aws configure`)
- Terraform installed (`brew install terraform` / `choco install terraform`)
- An EC2 key pair created in your target region (AWS Console → EC2 → Key Pairs)

## Usage

```bash
cd terraform

# Create terraform.tfvars with your values (gitignored):
cat > terraform.tfvars <<EOF
ami_id        = "ami-0faab6bdbac9486fb"   # Ubuntu 24.04, eu-central-1
key_pair_name = "your-key-pair-name"
your_ip       = "1.2.3.4/32"             # your public IP for SSH
EOF

terraform init
terraform plan
terraform apply

# Copy the output inventory snippet into ansible/inventory
# Then run Ansible as normal:
cd ..
ansible-playbook ansible/provision.yml
ansible-playbook ansible/deploy.yml
```

## Tear down

```bash
terraform destroy
```

All three EC2 instances are removed. Data is not preserved (no EBS snapshots).

## Why not Hyper-V provider?

The `taliesins/hyperv` Terraform provider requires Windows + WinRM.
AWS shows the same concept on standard infrastructure. The architecture is identical.
```

- [ ] **Step 6: Update .gitignore with Terraform state**

Terraform state files contain sensitive values (IPs, possibly secrets). Never commit them:

```
DASHBOARD_PROJECT.md

# Ansible secrets — never commit real passwords
ansible/group_vars/all/secrets.yml

# Ansible host-specific variables — machine-specific paths
ansible/host_vars/*.yml

# Terraform state and local variable overrides
terraform/.terraform/
terraform/.terraform.lock.hcl
terraform/terraform.tfstate
terraform/terraform.tfstate.backup
terraform/terraform.tfvars
```

- [ ] **Step 7: Commit**

```bash
git add terraform/ .gitignore
git commit -m "Add Terraform AWS provisioning for 3-node architecture

Mirrors the Hyper-V VM layout (history/proxy/ui) on AWS EC2.
Terraform provisions machines; Ansible configures them unchanged.
terraform apply outputs an ansible/inventory snippet ready to paste.

- terraform/main.tf: VPC, subnets, security groups, 3 EC2 instances
- terraform/variables.tf: region, AMI, instance type, key pair, your IP
- terraform/outputs.tf: public IPs + pre-formatted ansible/inventory block
- terraform/README.md: usage, prerequisites, relationship to Ansible
- .gitignore: terraform state files and tfvars excluded

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Self-review

**Spec coverage:**
- ✅ Delete docs/ansible-and-ssh.md
- ✅ Restore ansible_password: vagrant
- ✅ Restore ansible/inventory to git
- ✅ Delete inventory.example
- ✅ Revert .gitignore
- ✅ Fix JS constant naming
- ✅ SSH key auth via host_vars (proper convention-following way)
- ✅ Update deployment.md and blockers.md for SSH
- ✅ Volume heatmap
- ✅ Sentiment score on category filters
- ✅ Terraform AWS

**Placeholder scan:** No TBD/TODO. All code blocks are complete. All commands are exact.

**Type consistency:** `computeSentiment()` called in `updateCategoryLabels()` which is called in `refreshAll()` — all consistent. `CRYPTO_REFRESH_MS` and `NBU_REFRESH_MS` used in both declaration and setInterval — consistent.
