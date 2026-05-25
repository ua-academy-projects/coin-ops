# Multi-Cloud Terraform Infrastructure

> Cloud-agnostic infrastructure-as-code supporting **GCP** and **AWS** with a single codebase.

---

## Architecture

This project uses a unified **Dictionary/Map lookup pattern** alongside **JSON-based configurations**. Instead of separate `gcp.tfvars` and `aws.tfvars`, provider-specific equivalents are maintained in a single JSON dictionary, and environments specify logical values.

```
.
├── main.tf                      # Root orchestrator — calls modules
├── variables.tf                 # Core variables (cloud_provider, environment)
├── outputs.tf                   # Normalized outputs (same for both clouds)
├── locals.tf                    # JSON config loader + dictionary lookups
├── versions.tf                  # Provider declarations + backend config
├── providers.tf                 # Provider configurations with conditional skip flags
├── moved.tf                     # [TEMPORARY] State migration blocks
│
├── aws.tfvars                   # Minimal tfvars (cloud_provider = "aws", environment = "dev")
├── gcp.tfvars                   # Minimal tfvars (cloud_provider = "gcp", environment = "dev")
│
├── configs/
│   ├── mappings.json            # ALL provider dictionaries (instance types, disk types, DB engines, etc.)
│   ├── networking.json          # Default networking config (if env == default)
│   ├── compute.json             # Default compute config
│   ├── storage.json             # Default storage config
│   ├── database.json            # Default database config
│   │
│   └── environments/            # Environment-specific full configurations
│       ├── dev.json             # Dev topology
│       ├── staging.json         # Staging topology
│       └── prod.json            # Production topology
│
├── modules/
│   ├── networking/              # VPC + Subnets + Firewall/SGs
│   ├── compute/                 # VMs + SSH Keys
│   ├── storage/                 # GCS / S3 Buckets
│   └── database/                # Cloud SQL / RDS
│
└── bootstrap/
    ├── gcp.sh                   # GCP: project, SA, GCS state bucket
    └── aws.sh                   # AWS: IAM user, S3 bucket, DynamoDB lock
```

---

## Quick Start (AWS)

1. **Prerequisites**
   Install the [AWS CLI](https://aws.amazon.com/cli/) and authenticate (`aws configure`).

2. **Bootstrap** (first time only)
   Run `./bootstrap/aws.sh`. This creates the necessary S3 state bucket, DynamoDB lock table, and a dedicated IAM user. It generates `.env.aws`.

3. **Load environment**
   ```bash
   source .env.aws
   ```

4. **Switch backend**
   In `versions.tf`, comment out the `backend "gcs"` block and uncomment the `backend "s3"` block.

5. **Initialize**
   ```bash
   terraform init \
     -backend-config="bucket=${TF_VAR_state_bucket}" \
     -backend-config="key=terraform/state/terraform.tfstate" \
     -backend-config="region=${TF_VAR_aws_region}" \
     -backend-config="dynamodb_table=terraform-project-tf-lock"
   ```

6. **Plan & Apply** (using the `dev` environment)
   ```bash
   terraform plan -var-file=aws.tfvars
   terraform apply -var-file=aws.tfvars
   ```

*(For GCP, follow a similar process using `./bootstrap/gcp.sh`, `source .env.terraform`, and `gcp.tfvars`)*

---

## The Dictionary Pattern

The core mapping of concepts happens in `configs/mappings.json`.

For example, when an environment (`configs/environments/dev.json`) specifies `"instance_size": "micro"`, the modules use the dictionary to resolve it:
```json
"instance_type_map": {
  "micro": { "gcp": "e2-micro", "aws": "t3.micro" }
}
```

This pattern guarantees identical logical configurations deployed perfectly natively on either cloud provider.
