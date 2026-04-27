# Terraform Remote State

## Location

- **Backend type:** GCS (Google Cloud Storage)
- **Bucket:** `tfstate-project-8888321c-54a9-4dac-86d`
- **Path:** `terraform/state/default.tfstate`
- **Region:** us-central1

## Protection

- **Versioning:** Enabled — every state change creates a new version, allows rollback
- **Uniform bucket-level access:** Enabled — permissions managed via IAM only
- **Public access prevention:** Enabled — bucket cannot be made public
- **State locking:** Automatic via GCS — prevents concurrent modifications

## Who Has Access

| Principal | Access Level | How |
|-----------|-------------|-----|
| `terraform-sa@...` | Read/Write | `roles/storage.admin` |
| `kazachuk.gcp.learning@gmail.com` | Full | Project Owner |

## Important Rules

- Never edit the state file manually
- Never delete the state file
- Never commit state files to Git
- Use `terraform state` commands for state operations