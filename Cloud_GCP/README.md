# GCP Bootstrap & Terraform Infrastructure

## Overview

This project sets up a Google Cloud Platform environment from scratch using a **service account** — not a personal Google account. A bootstrap script prepares the GCP project, and Terraform uses the service account to create infrastructure.

This is the foundation for deploying the **CoinOps coin rates monitoring system** to the cloud.

---

## What is a Service Account?

A service account is a non-human identity in GCP. It's a "robot user" that exists to perform specific tasks.

**Why not use your personal Google account?**

| | Personal account | Service account |
|---|---|---|
| Tied to a person | Yes | No |
| Can share without risk | No | Yes (JSON key) |
| Works in CI/CD pipelines | No | Yes |
| Scope if key is leaked | Everything (Gmail, Drive, etc.) | Only assigned roles |
| Can be revoked independently | No | Yes |

A service account lets you share project access by giving someone a key file — without exposing your personal credentials. If access needs to be revoked, you delete the key. Your personal account is never affected.

---

## Project Structure

```
Cloud/
├── bootstrap.sh          # Sets up GCP project, service account, and state bucket
├── key.json              # Service account key (NEVER commit to Git)
├── .gitignore            # Excludes key.json and terraform.tfvars
└── terraform/
    ├── backend.tf        # Where Terraform stores state (GCS bucket)
    ├── provider.tf       # How Terraform connects to GCP
    ├── variables.tf      # Variable declarations (types, descriptions)
    ├── terraform.tfvars  # Actual variable values
    ├── main.tf           # Infrastructure resources (VMs, networks, firewalls)
    └── outputs.tf        # Values displayed after terraform apply
```

---

## File Descriptions

### bootstrap.sh

A shell script that runs **once, before Terraform**. It uses your personal `gcloud` authentication to create:

1. **GCP project** (`devops-intern-penina`) — a container for all resources
2. **Billing link** — connects the project to your $300 free trial credits
3. **APIs** — enables Compute Engine, Cloud Storage, IAM, Resource Manager
4. **Service account** (`terraform-sa`) — the identity Terraform will use
5. **IAM roles** — permissions for the service account:
   - `roles/compute.admin` — create/delete VMs, networks, firewalls
   - `roles/storage.admin` — manage the Terraform state bucket
   - `roles/iam.serviceAccountUser` — attach service accounts to VMs
6. **JSON key** (`key.json`) — the service account's credentials file
7. **GCS bucket** (`devops-intern-penina-tf-state`) — stores Terraform state

The script is **idempotent** — safe to run multiple times. It checks if each resource exists before creating it.

### backend.tf

Tells Terraform to store its state file in the GCS bucket. Without this, state would be a local file — if lost, Terraform forgets what it created.

The backend uses `key.json` to authenticate as the service account.

### provider.tf

Configures the connection to GCP: which provider plugin to use, which credentials, which project and region. All Terraform commands use these settings.

### variables.tf

Declares what variables the project needs — names, types, descriptions. No actual values here. Like a contract: "this project requires a project_id, region, zone, and credentials file."

### terraform.tfvars

The actual values for each variable. This is the only file a teammate would change to use different settings. Similar to `.env` in Docker Compose.

### main.tf

The actual infrastructure resources:

- **VPC Network** (`devops-network`) — an isolated virtual network, like a VirtualBox host-only network
- **Subnet** (`devops-subnet`, `10.0.1.0/24`) — IP range within the network, VMs get IPs from here
- **Firewall** (`allow-ssh`, port 22) — without this, all inbound traffic is blocked by default
- **VM** (`test-vm`, `e2-micro`) — Ubuntu 24.04 instance in Warsaw (europe-central2)

### outputs.tf

Displays the VM's public IP after `terraform apply` so you know where to SSH.

---

## How to Use

### Prerequisites

- Google Cloud account with billing enabled
- `gcloud` CLI installed
- `terraform` installed
- Authenticated with `gcloud auth login`

### Step 1: Run the bootstrap (once)

```bash
cd Cloud/
bash bootstrap.sh
```

This creates the project, service account, and state bucket. After this, your personal account steps back — Terraform uses only the service account.

### Step 2: Initialize Terraform

```bash
cd terraform/
terraform init
```

Downloads the Google provider plugin and connects to the GCS backend.

### Step 3: Validate and plan

```bash
terraform validate
terraform plan
```

- `validate` — checks syntax locally (no GCP connection)
- `plan` — shows what will be created (connects to GCP, dry run)

### Step 4: Apply

```bash
terraform apply
```

Creates the infrastructure. Type `yes` to confirm.

### Step 5: Verify

Check resources in the GCP Console:
- ☰ → Compute Engine → VM instances
- ☰ → VPC network → VPC networks
- ☰ → VPC network → Firewall
- ☰ → Cloud Storage → Buckets (state file)

Or via CLI:
```bash
gcloud compute instances list
gcloud compute networks list
gcloud compute firewall-rules list
```

### Step 6: Destroy (clean up)

```bash
terraform destroy
```

Deletes all resources Terraform created (VMs, networks, firewalls) to stop spending credits. The project, service account, and state bucket remain.

---

## Sharing Access with a Teammate

1. Send `key.json` via a **secure channel** (private Slack DM, encrypted message, USB drive)
2. **Never** send via email, Google Drive, or commit to Git
3. The teammate places `key.json` next to the `terraform/` folder
4. They run:

```bash
cd terraform/
terraform init
terraform plan
terraform apply
```

GCP sees all actions as `terraform-sa@devops-intern-penina.iam.gserviceaccount.com` — your personal account is never involved.

**To revoke access:**

```bash
gcloud iam service-accounts keys list --iam-account=terraform-sa@devops-intern-penina.iam.gserviceaccount.com
gcloud iam service-accounts keys delete KEY_ID --iam-account=terraform-sa@devops-intern-penina.iam.gserviceaccount.com
```

After deletion, the key file becomes useless even if the teammate still has it.

---

## Blockers & Problems Encountered

### 1. Script killed mid-run (Ctrl+C)

**Problem:** Pressed Ctrl+C during API enabling. Re-running the script failed with "project already exists" because `set -e` stopped at the first error.

**Fix:** Added idempotency checks — `if resource exists, skip; else create`. Now the script is safe to re-run.

### 2. Cyrillic character in folder name

**Problem:** Folder `Сloud_technologies` had a Cyrillic "С" instead of Latin "C". Git Bash `cd Cloud_technologies` failed with "No such file or directory."

**Fix:** Used Tab completion in Git Bash to autocomplete the correct path.

### 3. Two folders with similar names

**Problem:** VS Code saved the updated script in the Cyrillic folder, but Git Bash was in a different `Cloud` folder. Running the script executed the old version.

**Fix:** Verified the correct folder with `pwd` and `cat bootstrap.sh` before running.

---

## Key Concepts

| Concept | Description |
|---|---|
| **Service Account** | Non-human GCP identity with a JSON key, used by tools like Terraform |
| **IAM** | Identity and Access Management — who can do what on which resource |
| **Principle of Least Privilege** | Give only the permissions needed, nothing more |
| **Idempotency** | Running something once or ten times gives the same result |
| **Terraform State** | A file tracking what infrastructure exists, stored in GCS bucket |
| **VPC** | Virtual Private Cloud — isolated network for your resources |
| **GCS** | Google Cloud Storage — object storage for files (like S3 on AWS) |

---

## Next Steps

- Deploy the **CoinOps monitoring system** to GCP using this infrastructure
- Replace local VirtualBox VMs with GCP Compute Engine instances
- Set up proper networking between services (proxy, UI, RabbitMQ, history, PostgreSQL)
- Add CI/CD pipeline with GitHub Actions using the service account
- Configure Ansible to provision GCP VMs instead of local ones
