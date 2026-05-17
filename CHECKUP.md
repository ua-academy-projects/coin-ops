# Terraform Multi-Cloud Project — Full Audit Report

> Audited: 2026-05-02 | Auditor: Claude Sonnet 4.6 (senior DevOps persona)
> Scope: Full project read-only analysis — no files were modified.

---

## Executive Summary

This is a well-conceived learning project that successfully demonstrates core Terraform and multi-cloud competencies: remote state with locking on both clouds, cloud-agnostic JSON config driving infrastructure, modular architecture, pre-commit hooks with linting and security scanning, and a working jump host pattern with custom SSH port. The foundational thinking is solid — the JSON-as-single-source-of-truth with lookup tables for cloud translation is a legitimate production pattern. However, there is one critical security flaw in the AWS implementation that completely undermines the jump host security model: all security groups are attached to all instances, which means internal VMs are directly reachable from the internet, bypassing the jump host entirely. There are also smaller but real issues: the GCP startup script will silently fail to configure SSH on Debian (the default OS), hardcoded AMI IDs are tied to one region with no guard against misconfiguration, and a real GCP private key is sitting unencrypted on disk. Fixing the top 3 issues turns this from "works in happy path only" into a genuinely solid learning project. As a foundation for understanding real DevOps patterns, it's ahead of where most interns start.

---

## Strengths

1. **Remote state with locking on both clouds** — S3+DynamoDB for AWS (`infrastructure/environments/aws/backend.tf`), GCS for GCP (`infrastructure/environments/gcp/backend.tf`) with encryption enabled on both.

2. **Lock files committed** — Both `.terraform.lock.hcl` files are present in their environment directories. The `.gitignore` even includes a comment explaining this is intentional.

3. **JSON schema with VS Code integration** — All four config files have Draft-07 schemas with `additionalProperties: false` and the VS Code settings wire them up for live validation. This is production-grade developer tooling.

4. **Pre-commit hooks configured properly** — `.pre-commit-config.yaml` includes `terraform_fmt`, `terraform_validate`, `terraform_tflint`, `terraform_tfsec`, and `detect-private-key`. The last one is especially important given the project handles real credentials.

5. **`for_each` used everywhere instead of `count`** — Both the network and VM modules use `for_each = local.vms`, `for_each = local.networks`, etc. This means renaming a VM won't accidentally destroy and recreate a different one.

6. **Least-privilege public IP assignment** — Only `vm-4-jump` and `ec2-4-jump` have `assign_public_ip: true`. Internal VMs have no public IPs.

7. **SSH hardening is real** — `infrastructure/modules/aws/vm/main.tf` lines 24-27: `PermitRootLogin no`, `PasswordAuthentication no`, `X11Forwarding no`, custom port 47832. Not just boilerplate — these are the right settings.

8. **EBS volumes encrypted by default** — `infrastructure/modules/aws/vm/main.tf` line 13: `encrypted = true` in the root block device.

9. **Bootstrap scripts are idempotent** — Both `bootstrap/aws/bootstrap.sh` and `bootstrap/gcp/bootstrap.sh` check for existing resources before creating them. Safe to re-run.

10. **Cloud-agnostic abstractions are clean** — `small/medium/large`, `debian-12/ubuntu-22` map differently per cloud in the lookup tables. A developer can think in abstract terms and the lookup resolves the cloud-specific value.

---

## Critical Issues (Must Fix Before Production)

### CRITICAL-1: All AWS Security Groups are attached to all instances

**File:** `infrastructure/environments/aws/main.tf` line 84

**Current code:**
```hcl
security_group_ids = [for fw_name, fw in module.firewall : fw.security_group_id]
```

This iterates over every Security Group created in the environment and attaches them ALL to every instance. The AWS environment creates two SGs: `allow-ssh-jump-aws` (allows SSH from `37.52.252.218/32` on port 47832) and `allow-internal-aws`. Both get attached to every instance — jump host AND internal VMs alike.

**What breaks:** Internal VMs (`ec2-1`, `ec2-2`, `ec2-3`) are directly reachable from the trusted external IP on port 47832. They bypass the jump host entirely. The entire point of the jump host architecture is defeated.

**Root cause:** GCP uses network tags to select which firewall rules apply. AWS doesn't — Security Groups must be explicitly attached per instance based on the instance's role. The abstraction doesn't translate automatically.

**Fix:** Filter the SG list based on the VM's tags:
```hcl
security_group_ids = [
  for fw_name, fw in module.firewall : fw.security_group_id
  if length(setintersection(
    toset(lookup(each.value, "tags", [])),
    toset(local.firewall_rules[fw_name].target_tags)
  )) > 0
]
```

This only attaches a Security Group to a VM if the VM's tags overlap with the SG's `target_tags`. Jump hosts get the jump-host SG; internal VMs get the internal SG.

---

### CRITICAL-2: GCP startup script fails silently on Debian

**File:** `infrastructure/modules/gcp/vm/main.tf` line 53

**Current code:**
```bash
systemctl restart sshd
```

On Debian (the default OS, `debian-12`), the SSH service is named `ssh`, not `sshd`. `systemctl restart sshd` will fail with "Unit sshd.service not found." Because `set -e` is at the top of the script, the entire startup script exits at this line. The SSH port change (line 46) IS applied (sed modifies the file), but the SSH daemon never restarts to pick it up.

**Result:** Every GCP VM boots with SSH still on port 22 (the system default) despite the config saying 47832. The firewall rule only allows 47832, so the jump host becomes unreachable.

Compare with the AWS module at `infrastructure/modules/aws/vm/main.tf` line 31 which correctly does:
```bash
systemctl restart sshd || systemctl restart ssh
```

**Fix:**
```bash
systemctl restart ssh || systemctl restart sshd
```
Put `ssh` first since Debian is the default OS.

---

### CRITICAL-3: Hardcoded AMI IDs are region-specific with no guard

**File:** `infrastructure/environments/aws/lookups.tf` lines 14-18

**Current code:**
```hcl
os_image_lookup = {
  debian-12 = "ami-064519b8c76274859"  # Debian 12 in us-east-1
  debian-11 = "ami-0a7a4e87939439934"  # Debian 11 in us-east-1
  ubuntu-22 = "ami-0c7217cdde317cfec"  # Ubuntu 22.04 in us-east-1
}
```

If the AWS region in `config/general.json` is changed from `us-east-1` to anything else, these AMI IDs are invalid. AWS will fail with a cryptic error like `InvalidAMIID.NotFound`. There's no validation linking the region to the AMI lookup.

Also: AMIs are maintained by their publishers and IDs can be deprecated over time. Hardcoded IDs will eventually go stale.

**Fix — use data sources:**
```hcl
data "aws_ami" "debian_12" {
  most_recent = true
  owners      = ["136693071363"]  # Debian's official AWS account

  filter {
    name   = "name"
    values = ["debian-12-amd64-*"]
  }
}
```
Then reference `data.aws_ami.debian_12.id` instead of a hardcoded string. This is region-portable and always up-to-date.

---

### CRITICAL-4: Real GCP service account private key on disk

**File:** `sa-key.json` (project root)

The file contains a live RSA 2048-bit private key for `terraform-sa@project-8888321c-54a9-4dac-86d.iam.gserviceaccount.com`. It IS listed in `.gitignore` so it won't be committed by default. But it's sitting in the project directory, unencrypted, with no expiry.

**Risks:**
- `git add -f sa-key.json` or an IDE's "add all" dialog would silently commit it
- The pre-commit `detect-private-key` hook catches this only IF the file is staged — not before
- `bootstrap.sh.old` in the root shows there's already been at least one stale version of the bootstrap

**Fix:** Move the key outside the repo directory:
```bash
mkdir -p ~/.gcp-keys/
mv sa-key.json ~/.gcp-keys/project-terraform-sa.json
chmod 600 ~/.gcp-keys/project-terraform-sa.json
```
Then update `.env` to point there. The key material should never be inside any git-managed directory.

In a real company: use Workload Identity Federation instead of service account keys. For learning: at minimum keep the key outside the repo.

---

## Important Improvements (Should Fix)

### IMP-1: AWS firewall module silently drops multiple source CIDRs

**File:** `infrastructure/modules/aws/firewall/main.tf` line 29

```hcl
cidr_ipv4 = length(each.value.cidr_blocks) > 0 ? each.value.cidr_blocks[0] : null
```

Only `[0]` — the first CIDR — is used. If a rule has two source ranges, the second is silently ignored. There's no error or warning.

**Fix:** Create one ingress rule per CIDR block using a flattened for expression that iterates both rules and CIDRs.

---

### IMP-2: AWS subnet has `map_public_ip_on_launch = true` for all subnets

**File:** `infrastructure/modules/aws/network/main.tf` line 25

```hcl
map_public_ip_on_launch = true
```

This sets the subnet-level default to assign public IPs automatically. All subnets — including those for internal VMs — are configured this way. The instance-level `associate_public_ip_address = false` overrides it for specific instances, which is why it works currently. But if that flag is ever omitted for a new instance in this subnet, it gets a public IP without warning.

**Fix:**
```hcl
map_public_ip_on_launch = false
```

---

### IMP-3: GCP project-level SSH key overwrites all project metadata

**File:** `infrastructure/environments/gcp/main.tf` lines 4-8

```hcl
resource "google_compute_project_metadata" "ssh_keys" {
  metadata = {
    ssh-keys = "${local.general.ssh_user}:${var.ssh_public_key}"
  }
}
```

`google_compute_project_metadata` is a singular resource that manages ALL project metadata. If any other process or Terraform run manages a different metadata key, this will overwrite it.

**Fix:** Use `google_compute_project_metadata_item` to manage only the `ssh-keys` key:
```hcl
resource "google_compute_project_metadata_item" "ssh_keys" {
  key   = "ssh-keys"
  value = "${local.general.ssh_user}:${var.ssh_public_key}"
}
```

Also note: the SSH key is set BOTH project-wide here AND per-VM in the module's metadata block (`infrastructure/modules/gcp/vm/main.tf` line 32). Pick one approach — per-VM is more precise.

---

### IMP-4: AWS internal firewall rule missing ICMP and UDP

**File:** `config/firewall.json` lines 71-86

The `allow-internal-aws` rule only specifies `"protocol": "tcp"`. The equivalent GCP rule has `"protocols": ["tcp", "udp", "icmp"]`. Internal AWS instances can't ping each other, and UDP-based services won't work between them.

**Fix:** Add separate rules for `udp` and `icmp`, or use `"protocol": "all"` with `"ports": []`.

---

### IMP-5: `general.json` has duplicated fields for GCP

**File:** `config/general.json`

```json
{
  "providers": {
    "gcp": {
      "project_id": "...",
      "region": "us-central1",
      "zone": "us-central1-a"
    }
  },
  "project_id": "...",   ← duplicate
  "region": "us-central1",   ← duplicate
  "zone": "us-central1-a"    ← duplicate
}
```

The GCP environment reads top-level fields (`local.general.project_id`, etc.) while AWS reads from the nested `providers.aws.*` path. These can drift out of sync. Consolidate so GCP reads from `providers.gcp.*` the same way AWS reads from `providers.aws.*`.

---

### IMP-6: Provider version constraints allow too much drift

**Files:** `infrastructure/environments/aws/versions.tf`, `infrastructure/environments/gcp/versions.tf`

```hcl
version = ">= 5.0, < 6.0"   # allows anything from 5.0.0 to 5.99.x
```

This is a 100-minor-version range. The lock file pins the actual version, so it works in practice. But the constraint documents intent. Use `~> 5.45` (GCP) and `~> 5.100` (AWS) to allow patch releases but not minor version jumps.

---

### IMP-7: `bootstrap/gcp/bootstrap.sh` creates an outdated `terraform/` directory

**File:** `bootstrap/gcp/bootstrap.sh` line 257

The function `create_terraform_files()` creates a flat `terraform/` directory. The actual infrastructure lives in `infrastructure/environments/gcp/`. Running the bootstrap would create a stale `terraform/` directory that confuses new developers. Either delete `create_terraform_files()` from the script or update it to document the real structure.

---

### IMP-8: `.gitignore` line 40 has a malformed pattern

**File:** `.gitignore` line 40

```gitignore
*.bak.vscode/*.code-workspace
```

This matches paths like `something.bak.vscode/project.code-workspace` — which doesn't exist. It was almost certainly meant to be two separate lines:
```gitignore
*.bak
.vscode/*.code-workspace
```

---

### IMP-9: No validation between AWS region and hardcoded AMI IDs

**Files:** `config/general.json`, `infrastructure/environments/aws/lookups.tf`

There's no Terraform check asserting the region is `us-east-1` when using the hardcoded AMIs. At minimum, add a local that fails loudly:

```hcl
locals {
  _assert_region = (
    local.general.providers.aws.region == "us-east-1"
    ? true
    : tobool("ERROR: AMI IDs in lookups.tf are only valid for us-east-1. Update AMIs or use data sources.")
  )
}
```

---

## Nice-to-Have Enhancements

### NTH-1: AWS outputs are missing jump host convenience outputs

The GCP environment has `output "jump_host_ip"` and `output "ssh_command"`.
The AWS environment (`infrastructure/environments/aws/outputs.tf`) has neither.

Add:
```hcl
output "jump_host_ip" {
  description = "Public IP of the AWS jump host"
  value       = module.vm["ec2-4-jump"].public_ip
}

output "ssh_command" {
  description = "SSH command to connect to the AWS jump host"
  value       = "ssh -A -i ~/.ssh/aws_jump -p ${local.general.ssh_port} ${local.resolved_default_ssh_user}@${module.vm["ec2-4-jump"].public_ip}"
}
```

---

### NTH-2: AWS modules lack README.md files

GCP modules have `README.md` files. AWS modules (`infrastructure/modules/aws/vm/`, etc.) have none. The `terraform_docs` pre-commit hook in `.pre-commit-config.yaml` would auto-generate these. Run:
```bash
pre-commit run terraform_docs --all-files
```

---

### NTH-3: `machine_type` validation in GCP VM module is too restrictive

**File:** `infrastructure/modules/gcp/vm/variables.tf` lines 26-29

```hcl
validation {
  condition = contains(["e2-micro", "e2-small", "e2-medium"], var.machine_type)
}
```

If you add a new machine type to the lookup table, you must also update this validation. Consider validating the abstraction key (`small/medium/large`) in the config schema rather than the resolved GCP value in the module.

---

### NTH-4: `firewall.schema.json` doesn't require `protocol` OR `protocols`

**File:** `config/schemas/firewall.schema.json`

A firewall rule could omit both `protocol` and `protocols`. Terraform would fail at runtime. Use JSON Schema `oneOf` or `anyOf` to require at least one:

```json
"oneOf": [
  {"required": ["protocol"]},
  {"required": ["protocols"]}
]
```

---

### NTH-5: `bootstrap.sh.old` in project root

The file exists at `bootstrap.sh.old` and is gitignored by `*.old`. Delete it — stale files create confusion about which bootstrap to use.

---

### NTH-6: Budget alerts / auto-shutdown for learning environment

No budget cap or auto-shutdown for VMs. Consider:
- A GCP budget with an email alert at $10/month
- An AWS Budget with a threshold at $10/month
- An instance schedule to stop VMs outside working hours

---

## Specific Recommendations Summary Table

| # | File | Line | Issue | Severity |
|---|------|------|-------|----------|
| 1 | `infrastructure/environments/aws/main.tf` | 84 | All SGs attached to all instances | Critical |
| 2 | `infrastructure/modules/gcp/vm/main.tf` | 53 | `systemctl restart sshd` fails on Debian | Critical |
| 3 | `infrastructure/environments/aws/lookups.tf` | 14-18 | Hardcoded region-specific AMIs | Critical |
| 4 | `sa-key.json` | — | Real private key inside repo directory | Critical |
| 5 | `infrastructure/modules/aws/firewall/main.tf` | 29 | Only first CIDR applied per rule | Important |
| 6 | `infrastructure/modules/aws/network/main.tf` | 25 | `map_public_ip_on_launch = true` on all subnets | Important |
| 7 | `infrastructure/environments/gcp/main.tf` | 4-8 | `google_compute_project_metadata` wipes all metadata | Important |
| 8 | `config/firewall.json` | 71-86 | AWS internal rule missing ICMP/UDP | Important |
| 9 | `config/general.json` | — | Duplicated GCP fields (project_id, region, zone) | Important |
| 10 | `.gitignore` | 40 | Malformed gitignore pattern | Important |
| 11 | `infrastructure/environments/aws/versions.tf` | — | Version constraints too broad | Minor |
| 12 | `bootstrap/gcp/bootstrap.sh` | 257 | Creates stale `terraform/` directory structure | Minor |
| 13 | `bootstrap.sh.old` | — | Stale file in repo root | Minor |
| 14 | `infrastructure/environments/aws/outputs.tf` | — | No jump host IP or SSH command output | Nice-to-have |
| 15 | `infrastructure/modules/aws/*/` | — | No README.md files | Nice-to-have |

---

## Production Readiness Score

| Dimension | Score | Notes |
|-----------|-------|-------|
| **Architecture** | 7/10 | Good patterns; GCP→AWS translation has the SG attachment gap |
| **Security** | 5/10 | Critical SG bug + key on disk bring the score down significantly |
| **Terraform Practices** | 7/10 | `for_each`, modules, lock files, pre-commit all solid; version pinning loose |
| **Documentation** | 5/10 | GCP modules have READMEs, AWS don't; no deploy runbook or troubleshooting guide |
| **Multi-cloud Implementation** | 6/10 | Abstraction concept is correct; AWS SG assignment and missing ICMP rules are gaps |
| **Overall** | **6/10** | Strong foundation with two showstopper bugs and several meaningful gaps |

---

## Top 5 Action Items

**1. Fix AWS Security Group attachment** — `infrastructure/environments/aws/main.tf` line 84

Filter SGs by tag intersection instead of attaching all to all. This is the most impactful security fix — right now the jump host architecture doesn't work as intended in AWS. Internal VMs are reachable directly from the internet.

**2. Fix GCP startup script SSH service name** — `infrastructure/modules/gcp/vm/main.tf` line 53

Change `systemctl restart sshd` to `systemctl restart ssh || systemctl restart sshd`. Without this, the SSH port configuration silently fails on Debian and VMs are unreachable on the custom port.

**3. Replace hardcoded AMI IDs with `aws_ami` data sources** — `infrastructure/environments/aws/lookups.tf` lines 14-18

Hardcoded IDs break on region change and go stale over time. Data sources are the standard approach and resolve automatically.

**4. Move `sa-key.json` outside the repo directory** — project root

Even gitignored, having a live private key inside a project directory is a bad habit. Store credentials outside the repo in `~/.gcp-keys/` or a secrets manager.

**5. Fix AWS internal firewall rule to include ICMP and UDP** — `config/firewall.json` lines 71-86

Internal VMs can't ping each other or use UDP services in AWS. Mirror the GCP rule to include all necessary protocols.
