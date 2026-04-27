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

Research and document answers to:

- What is a **service account** in GCP? How is it different from a user account?
- Why is it a best practice to run infrastructure projects under a service account instead of your personal account?
- Key insight: a service account lets you **share project access** with authorized people (e.g., teammates, mentors) by giving them the service account key — without ever exposing your personal credentials.
- What is the **principle of least privilege** and how does it apply to service account permissions?

### 3. Learn Google Cloud CLI (`gcloud`)

- Install `gcloud` CLI on your machine.
- Understand the basic workflow: `gcloud auth login`, `gcloud config set project`, `gcloud projects create`, etc.
- `gcloud` can create service accounts, projects, configure permissions, enable APIs, and more.
- This is the tool you will use in the bootstrap script.

### 4. Write the Bootstrap Script

Create a shell script (`bootstrap.sh`) that does the following:

1. **Creates a GCP project** (or uses an existing one).
2. **Enables required APIs** — at minimum: Compute Engine, Cloud Storage, IAM.
3. **Creates a service account** dedicated to Terraform.
4. **Assigns IAM roles** to the service account — research which roles are needed so the service account can create VMs, networks, firewall rules, and other infrastructure.
5. **Creates a JSON key** for the service account — this key file is what Terraform (and teammates) will use to authenticate.
6. **Creates a GCS bucket** for Terraform remote state — GCP's equivalent of Amazon S3. This is where Terraform stores its `.tfstate` file so the state is shared and not lost.
7. **Grants the service account access** to the state bucket.

### 5. Terraform Must Use the Service Account

- Terraform must authenticate as the **service account**, not your personal Google account.
- The service account key (JSON file) created by the bootstrap script is passed to Terraform via the `GOOGLE_APPLICATION_CREDENTIALS` environment variable or the `credentials` field in the provider block.
- This is a hard requirement — your personal account should never be used by Terraform.

### 6. Sharing Access

- The service account key can be given to a teammate so they can run Terraform against the same project.
- Document how a teammate would use the key to authenticate and run Terraform.

### 7. Document Blockers and Problems

- Record every issue you encounter during setup (billing, API enablement, permission errors, quota limits, etc.).
- For each problem, document: what happened, why it happened, and how you fixed it.

### 8. Terraform Remote State

- Understand why Terraform needs remote state (vs. local state file).
- The GCS bucket for state must be created **before** Terraform runs — that is why it is part of the bootstrap script.
- Research: what happens if two people run Terraform at the same time? How does state locking work with GCS?

---

## Deliverables

| Deliverable | Description |
|---|---|
| `bootstrap.sh` | Shell script that sets up the GCP project, service account, IAM roles, and state bucket |
| `README.md` | Documentation: what a service account is, why it is used, how the bootstrap works, how to share access |
| Blockers log | Notes on every problem encountered and how it was resolved |
| Terraform backend config | Example of how Terraform is configured to use the GCS bucket for state and the service account for auth |

---

## What the Bootstrap Prepares

```
bootstrap.sh (runs once, uses your personal gcloud auth)
    ├── GCP Project created
    ├── APIs enabled (Compute, Storage, IAM)
    ├── Service Account created with proper IAM roles
    ├── SA key (JSON) exported
    └── GCS bucket for Terraform state created

After bootstrap → Terraform uses the service account to create infrastructure
```

---

## Key Concepts to Research

- **IAM (Identity and Access Management)** — roles, permissions, policies
- **Service Account vs User Account** — differences, use cases
- **Principle of Least Privilege** — give only the permissions needed, nothing more
- **GCS (Google Cloud Storage)** — buckets, objects, access control
- **Terraform Remote State** — backend configuration, state locking
- **`gcloud` CLI** — project management, IAM, service accounts, APIs
- **`GOOGLE_APPLICATION_CREDENTIALS`** — environment variable for service account auth

---

## Important Notes

- The bootstrap script should be **idempotent** — safe to run multiple times without breaking anything.
- Never commit the service account key (JSON) to Git — add it to `.gitignore`.
- Use meaningful resource names (e.g., `terraform-sa` for the service account, `tf-state-bucket` for the bucket).
