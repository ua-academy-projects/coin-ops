# GCP Bootstrap & Terraform Infrastructure

## Overview

This project sets up a Google Cloud Platform environment from scratch using a **service account** — not a personal Google account. A bootstrap script prepares the GCP project, and Terraform uses the service account to create infrastructure.

The goal is to prove the full flow: bootstrap → service account → remote state → Terraform creates resources.

---

## What is a Service Account?

A service account is a non-human identity in GCP — a "robot user" that authenticates with a JSON key file instead of a password.

**Why not use your personal Google account?**

| | Personal account | Service account |
|---|---|---|
| Tied to a person | Yes | No |
| Can share without risk | No | Yes (JSON key) |
| Works in CI/CD pipelines | No | Yes |
| Scope if key is leaked | Everything (Gmail, Drive, etc.) | Only assigned roles |
| Can be revoked independently | No | Yes |

Using a service account means:
- The project is not tied to one person's login
- Access can be shared by handing over a key file — no personal credentials exposed
- Permissions follow the **principle of least privilege** — only what's needed, nothing more
- The same approach works for CI/CD automation in the future

---

## IAM Roles — What and Why

IAM (Identity and Access Management) controls who can do what on which resource. We assigned three roles to the service account:

| Role | Why needed |
|---|---|
| `roles/compute.admin` | Create/delete VMs, networks, subnets, firewall rules |
| `roles/storage.admin` | Read/write Terraform state file in the GCS bucket |
| `roles/iam.serviceAccountUser` | Required by GCP to attach a service account to VMs during creation — without it, VM creation fails |

These are the **minimum roles** needed. No Owner, no Super Admin. If the key is compromised, the attacker can only manage compute resources and storage — not billing, IAM policies, or other GCP services.

---

## Terraform Flow

Terraform works in stages. Each command has a specific purpose:

| Command | What it does |
|---|---|
| `terraform validate` | Checks `.tf` file syntax locally. No GCP connection. Instant. |
| `terraform init` | Downloads provider plugins, connects to GCS backend, verifies credentials work. |
| `terraform plan` | Compares code vs state vs real infrastructure. Shows what will change. Does not change anything. |
| `terraform apply` | Executes the plan. Creates/updates/deletes resources. Updates the state file. |
| `terraform destroy` | Deletes all resources managed by Terraform. State becomes empty. |

**Terraform compares three things on every `plan`:**
1. Your `.tf` code — what you **want** to exist (desired state)
2. The state file — what Terraform **thinks** exists
3. Real GCP infrastructure — what **actually** exists

If all three match, `plan` shows "No changes." If they differ, `plan` shows what needs to change.

---

## Terraform Remote State

### What is state?

A JSON file that tracks every resource Terraform manages — IDs, IPs, configurations. Terraform needs it to know what exists and what to change.

### Why remote, not local?

| | Local state | Remote state (GCS bucket) |
|---|---|---|
| Shared between teammates | No | Yes |
| Safe if laptop breaks | No | Yes |
| Works with CI/CD | No | Yes |
| Supports locking | No | Yes |

### Where is our state?

Stored in `gs://devops-intern-penina-tf-state/terraform/state/` — a GCS bucket in Warsaw (europe-central2). The bucket was created by the bootstrap script before Terraform ran.

### Who has access?

Only the service account (`terraform-sa`) with `roles/storage.admin` and the project owner.

### State locking

If two people run `terraform apply` at the same time, GCS backend locks the state file. The second person gets a "state locked" error and must wait. This prevents two people from creating conflicting infrastructure simultaneously.

### Security

State files can contain sensitive data in plain text (passwords, IPs, keys). That's why:
- State is **never** stored in Git
- State is **never** shared as a text file
- The bucket has access controls — only authorized identities can read it

---

## State Drift

**Drift** = the difference between what Terraform thinks exists (state file) and what actually exists in GCP.

### How it happens

Someone manually changes a resource in the GCP Console — deletes a firewall rule, resizes a VM, modifies a network. Terraform doesn't know about this until the next `terraform plan`.

### Why it's dangerous

- Terraform might try to revert the manual change (unexpected)
- Terraform might fail because the resource is in an unexpected state
- Multiple people making manual changes creates chaos

### The rule

Never modify Terraform-managed resources manually. All changes go through `.tf` files → `plan` → `apply`.

### If drift happens

1. Run `terraform plan` — it shows the difference
2. Decide: update your `.tf` code to match reality, or let Terraform overwrite the manual change
3. Never delete the state file to "fix" drift — that makes Terraform forget everything

---

## Project Structure

```
Cloud_GCP/
├── bootstrap.sh              # GCP setup: project, SA, roles, key, bucket
├── gcp_bootstrap_task.md     # Task description and acceptance criteria
├── README.md                 # This file
├── key.json                  # SA key (NOT in Git)
├── .gitignore                # Excludes secrets and generated files
└── terraform/
    ├── backend.tf            # Remote state config (GCS bucket)
    ├── provider.tf           # GCP provider + required plugins
    ├── variables.tf          # Variable declarations (types, descriptions)
    ├── terraform.tfvars      # Actual values (NOT in Git)
    ├── main.tf               # Infrastructure resources
    └── outputs.tf            # Values displayed after apply
```

### File Descriptions

**`bootstrap.sh`** — runs once, before Terraform. Uses your personal `gcloud` auth to create the project, service account, IAM roles, key, and state bucket. Idempotent — safe to re-run. If a resource already exists, it skips creation.

**`backend.tf`** — tells Terraform where to store state. Points to the GCS bucket. Uses `key.json` to authenticate. Cannot use variables (Terraform limitation).

**`provider.tf`** — configures the GCP connection: which plugin version, which credentials, which project and region.

**`variables.tf`** — declares what variables the project needs (names, types, descriptions). No actual values — those go in `terraform.tfvars`.

**`terraform.tfvars`** — actual values for each variable. The only file a teammate would change. Not in Git because it contains the credentials path.

**`main.tf`** — the infrastructure resources: VPC network, subnet, firewall rule, VM.

**`outputs.tf`** — displays useful info after `terraform apply` (like the VM's public IP).

---

## How to Use

### Prerequisites

- Google Cloud account with billing enabled
- `gcloud` CLI installed and authenticated (`gcloud auth login`)
- Terraform installed (`terraform --version`)

### Step 1: Run the bootstrap (once)

```bash
bash bootstrap.sh
```

Creates the project, service account, and state bucket. After this, your personal account steps back.

### Step 2: Initialize Terraform

```bash
cd terraform/
terraform init
```

### Step 3: Validate, plan, apply

```bash
terraform validate    # syntax check
terraform plan        # dry run — what will be created?
terraform apply       # create resources (type 'yes' to confirm)
```

### Step 4: Verify

In GCP Console:
- ☰ → Compute Engine → VM instances
- ☰ → VPC network → VPC networks
- ☰ → VPC network → Firewall
- ☰ → Cloud Storage → Buckets (check state file exists)

Via CLI:
```bash
gcloud compute instances list
gcloud compute networks list
gcloud compute firewall-rules list
```

### Step 5: Clean up

```bash
terraform destroy
```

Deletes all Terraform-managed resources. Project, service account, and bucket remain.

---

## Sharing Access with a Teammate

### Giving access

1. Send `key.json` via a **secure channel** — private Slack DM, encrypted messaging, USB drive
2. **Never** send via email, Google Drive, or Git
3. Teammate places `key.json` next to the `terraform/` folder
4. Teammate creates their own `terraform.tfvars` with the correct paths
5. Runs: `terraform init` → `terraform plan` → `terraform apply`

GCP sees all actions as `terraform-sa@devops-intern-penina.iam.gserviceaccount.com` — the teammate's personal account is never involved.

### Revoking access

```bash
# List all keys
gcloud iam service-accounts keys list \
  --iam-account=terraform-sa@devops-intern-penina.iam.gserviceaccount.com

# Delete the compromised key
gcloud iam service-accounts keys delete KEY_ID \
  --iam-account=terraform-sa@devops-intern-penina.iam.gserviceaccount.com
```

After deletion, the key file becomes useless even if the teammate still has it.

---

## What Was Created

### By bootstrap.sh (personal account, once):

| Resource | Value |
|---|---|
| GCP project | `devops-intern-penina` |
| APIs enabled | Compute Engine, Cloud Storage, IAM, Resource Manager |
| Service account | `terraform-sa@devops-intern-penina.iam.gserviceaccount.com` |
| IAM roles | `compute.admin`, `storage.admin`, `iam.serviceAccountUser` |
| Key file | `key.json` |
| State bucket | `gs://devops-intern-penina-tf-state` |

### By Terraform (service account):

| Resource | Name | Details |
|---|---|---|
| VPC network | `devops-network` | Custom mode, no auto-subnets |
| Subnet | `devops-subnet` | `10.0.1.0/24`, Warsaw (europe-central2) |
| Firewall | `allow-ssh` | TCP port 22, from anywhere |
| VM | `test-vm` | `e2-micro`, Ubuntu 24.04, public IP assigned |

---

## Blockers & Problems Encountered

### 1. Script killed mid-run (Ctrl+C)

**Problem:** Pressed Ctrl+C during API enabling. Re-running the script failed with "project already exists."

**Root cause:** Script was not idempotent — assumed resources don't exist.

**Fix:** Added `if/else` checks: if resource exists → skip, else → create. Now safe to re-run.

**DevOps lesson:** Idempotency — running something once or ten times gives the same result. Same concept as Ansible playbooks.

### 2. Cyrillic character in folder name

**Problem:** Folder had a Cyrillic "С" instead of Latin "C". `cd` failed in Git Bash.

**Fix:** Used Tab completion. Renamed folder to Latin characters.

### 3. VS Code and Git Bash in different folders

**Problem:** Two folders with similar names. Edited file in one, ran script from another.

**Fix:** Verified path with `pwd` and file content with `cat` before running.

---

## Secrets & Credentials Rules

**Never:**
- Push `key.json` to GitHub
- Store credentials in plain text in the repository
- Send keys via email or public channels
- Use personal account for Terraform as the primary flow
- Give the service account Owner/Super Admin "just to make it work"

**Allowed for learning:**
- Local `key.json` file excluded via `.gitignore`
- Local `terraform.tfvars` excluded via `.gitignore`
- These files never leave your machine unless intentionally shared via secure channel

---

## Next Steps

- Deploy CoinOps monitoring system to GCP using this infrastructure
- Replace local VirtualBox VMs with GCP Compute Engine instances
- Set up proper networking between services (proxy, UI, RabbitMQ, history, PostgreSQL)
- Add CI/CD pipeline with GitHub Actions using the service account
- Configure Ansible to provision GCP VMs
- `terraform destroy` to clean up test resources and save credits
