# Service Account Permissions

## Service Account

- **Name:** terraform-sa
- **Email:** terraform-sa@project-8888321c-54a9-4dac-86d.iam.gserviceaccount.com
- **Purpose:** Used by Terraform to manage GCP infrastructure

## Assigned IAM Roles

| Role | Purpose |
|------|---------|
| `roles/storage.admin` | Read/write Terraform state in GCS bucket |
| `roles/compute.networkAdmin` | Create and manage VPC networks and subnets |
| `roles/compute.instanceAdmin.v1` | Create and manage VM instances |
| `roles/compute.securityAdmin` | Create and manage firewall rules |
| `roles/serviceusage.serviceUsageAdmin` | Enable/disable GCP APIs |
| `roles/iam.serviceAccountUser` | Attach service accounts to VM instances |

## Authentication

Terraform authenticates via a JSON key file (`sa-key.json`).
The key path is set through the `GOOGLE_APPLICATION_CREDENTIALS` environment variable.

**Security notes:**

- The key file is excluded from Git via `.gitignore`
- The key file permissions are set to `600` (owner read/write only)
- In production, use Workload Identity Federation instead of JSON keys