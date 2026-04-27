# Task: GCP Bootstrap with Service Account & Terraform State

## Objective

Create a **bootstrap shell script** that prepares a Google Cloud Platform project for infrastructure management via Terraform, using a **dedicated service account** — not your personal Google account.

This script runs **before** Terraform. It is the prerequisite setup that makes Terraform possible.

---

## Steps

### 1. Register on GCP

- Create a Google Cloud account and activate the free tier ($300 credits).
- Familiarize yourself with the GCP Console (web UI).

### 2. Understand Service Accounts

- **Service Account** — a non-human identity in GCP. A "robot user" with a JSON key file instead of a password.
- **User Account** — your personal Google account (Gmail, Drive, YouTube). Tied to you as a person.
- **Key difference:** a service account can be shared via a key file without exposing personal credentials. If the key leaks, you revoke it — your personal account is unaffected.
- **Principle of Least Privilege:** give only the permissions needed, nothing more. Never assign Owner/Super Admin unless absolutely justified.

### 3. Why Service Account, Not Personal Account?

| | Personal account | Service account |
|---|---|---|
| Tied to a person | Yes | No |
| Can share without risk | No | Yes (JSON key) |
| Works in CI/CD pipelines | No | Yes |
| Scope if key is leaked | Everything (Gmail, Drive, etc.) | Only assigned roles |
| Can be revoked independently | No | Yes |

### 4. Learn Google Cloud CLI (`gcloud`)

- Install `gcloud` CLI on your machine.
- `gcloud` can create projects, service accounts, configure permissions, enable APIs, and more.
- This is the tool used in the bootstrap script.

### 5. Write the Bootstrap Script

Shell script (`bootstrap.sh`) that does:

1. **Creates a GCP project** (or skips if exists — idempotent).
2. **Links billing** to the project.
3. **Enables required APIs** — Compute Engine, Cloud Storage, IAM, Resource Manager.
4. **Creates a service account** dedicated to Terraform.
5. **Assigns IAM roles** — minimum needed, not Owner/Super Admin.
6. **Creates a JSON key** for the service account.
7. **Creates a GCS bucket** for Terraform remote state.

### 6. Terraform Remote State

- Terraform state is a file tracking what infrastructure exists.
- Must NOT be stored in Git, in the repo, or as an unprotected local file.
- Must be stored in a GCS bucket (created by bootstrap, before `terraform init`).
- State may contain sensitive data in plain text — never push to Git or share as a text file.
- Remote state must be accessible to all team members and future CI/CD.
- **State locking:** GCS backend supports locking — if two people run Terraform simultaneously, the second one waits until the first finishes.

### 7. Run Terraform Using the Service Account

- Terraform authenticates as the service account (via `key.json`), NOT as personal account.
- Verify that the service account has enough permissions for the test resource but no excessive admin rights.

### 8. Create a Minimal Test Resource

Not a full product infrastructure. Just enough to prove the flow works:
- A network, a firewall rule, a VM — or any minimal GCP resource.
- The goal is to prove: bootstrap works → SA created → backend works → Terraform runs with remote state → resource created via SA.

---

## Terraform Flow — Must Be Able to Explain

| Command | What it does |
|---|---|
| `terraform validate` | Checks syntax locally. No GCP connection. Like a spell-checker. |
| `terraform init` | Downloads provider plugins, connects to GCS backend, verifies credentials. |
| `terraform plan` | Compares `.tf` files against state and real infrastructure. Shows what will change. Dry run. |
| `terraform apply` | Executes the planned changes. Creates/updates/deletes resources. Updates state file. |
| `terraform destroy` | Deletes all resources managed by Terraform. Updates state to empty. |

**Important:** Terraform compares THREE things:
1. Your `.tf` code (desired state)
2. The state file (what Terraform thinks exists)
3. Real infrastructure (what actually exists in GCP)

---

## State Drift — Must Understand

**Drift** = the difference between what Terraform thinks exists (state file) and what actually exists in GCP.

**How it happens:** someone manually changes a resource in GCP Console — deletes a firewall rule, resizes a VM, modifies a network. Terraform doesn't know about this change until the next `terraform plan`.

**Why it's dangerous:** Terraform might try to "fix" the drift by reverting the manual change, or it might fail because the resource is in an unexpected state.

**Rule:** never modify Terraform-managed resources manually. All changes go through `.tf` files → `plan` → `apply`.

**What if drift happens?** Run `terraform plan` — it will show the difference. Then decide: either update your `.tf` code to match reality, or let Terraform overwrite the manual change.

---

## IAM Roles — Justification

| Role | Why needed |
|---|---|
| `roles/compute.admin` | Terraform needs to create/delete VMs, networks, firewall rules |
| `roles/storage.admin` | Terraform needs to read/write state file in the GCS bucket |
| `roles/iam.serviceAccountUser` | GCP requires this to attach a service account to VMs during creation |

These are the minimum roles needed. No Owner, no Super Admin.

---

## Sharing Access (Key Handoff)

1. Send `key.json` via a **secure channel** (private Slack DM, encrypted message, USB)
2. **Never** via email, Google Drive, or Git
3. Teammate places `key.json` in the expected path
4. Runs: `terraform init` → `terraform plan` → `terraform apply`
5. GCP sees all actions as the service account, not as the teammate

**To revoke:**
```bash
gcloud iam service-accounts keys list --iam-account=SA_EMAIL
gcloud iam service-accounts keys delete KEY_ID --iam-account=SA_EMAIL
```

---

## Acceptance Criteria

- [x] Separate GCP project for testing
- [x] Bootstrap script creates/configures base GCP resources
- [x] Service Account created
- [x] SA has no excessive Owner/Super Admin permissions — justified minimum roles only
- [x] GCS bucket for Terraform remote state exists
- [x] Terraform state NOT stored in Git
- [x] Terraform state NOT stored as primary local state
- [x] Terraform runs as Service Account
- [x] `terraform init` connects to remote backend
- [x] `terraform plan` shows expected changes
- [x] `terraform apply` creates minimal test resource
- [x] Can explain: where state is, who has access, why it's safer than local file
- [x] Can explain: init, plan, apply, state
- [x] Understands drift and why manual cloud changes cause problems

---

## Blockers & Problems Encountered

### 1. Script killed mid-run (Ctrl+C)

**Problem:** Pressed Ctrl+C during API enabling. Re-running the script failed with "project already exists" because `set -e` stopped at the first error.

**Root cause:** Script was not idempotent — it assumed resources don't exist.

**Fix:** Added `if/else` checks before creating each resource. Now the script checks "does this exist?" before trying to create it.

### 2. Cyrillic character in folder name

**Problem:** Folder `Сloud_technologies` had a Cyrillic "С" instead of Latin "C". Git Bash `cd Cloud_technologies` failed with "No such file or directory."

**Fix:** Used Tab completion in Git Bash to autocomplete the correct path. Renamed folder to use Latin characters.

### 3. Two folders with similar names

**Problem:** VS Code saved the updated script in the Cyrillic folder, but Git Bash was in a different `Cloud` folder. Running the script executed the old version without idempotency checks.

**Fix:** Verified the correct path with `pwd` and `cat bootstrap.sh` before running. Lesson: always verify you're editing and running the same file.

---

## Project Structure

```
Cloud_GCP/
├── bootstrap.sh              # GCP setup: project, SA, roles, key, bucket
├── gcp_bootstrap_task.md     # This task description
├── README.md                 # Documentation and usage guide
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

---

## What Was Created

### By bootstrap.sh (run once, personal account):
- GCP project: `devops-intern-penina`
- APIs: Compute Engine, Cloud Storage, IAM, Resource Manager
- Service account: `terraform-sa@devops-intern-penina.iam.gserviceaccount.com`
- IAM roles: `compute.admin`, `storage.admin`, `iam.serviceAccountUser`
- Key file: `key.json`
- State bucket: `gs://devops-intern-penina-tf-state`

### By Terraform (runs as service account):
- VPC network: `devops-network`
- Subnet: `devops-subnet` (`10.0.1.0/24`, Warsaw)
- Firewall: `allow-ssh` (port 22)
- VM: `test-vm` (`e2-micro`, Ubuntu 24.04)

---

## Next Steps

- Deploy CoinOps monitoring system to GCP
- Replace VirtualBox VMs with GCP Compute Engine instances
- Set up networking between services
- CI/CD pipeline with GitHub Actions using the service account
- Ansible provisioning on GCP VMs
- `terraform destroy` to clean up test resources and save credits

---

## Out of Scope

- Full cloud infrastructure for the product
- CI/CD deployment pipeline
- Production-grade secrets management
- Full network architecture
- Migration of entire product to GCP
- Google Deployment Manager
- Shared team project (each student has their own)
