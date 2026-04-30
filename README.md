# GCP Terraform Bootstrap

Bootstrap a GCP project for Terraform using a Service Account, remote state in GCS,
and a modular infrastructure with JSON-driven configuration.

## Architecture

    Local Machine (Mac)
        |
        | ssh -A -i ~/.ssh/gcp_jump -p 47832 terraform@JUMP_HOST_IP
        v
    +--------------------------------------------------+
    |           VPC: terraform-network                 |
    |           Subnet: 10.0.0.0/24                    |
    |                                                  |
    |   +-----------------+                            |
    |   |   vm-4-jump     | <-- public IP, port 47832  |
    |   +--------+--------+                            |
    |            |                                     |
    |      +-----+-----+                               |
    |      v     v     v                               |
    |   +----++----++----+                             |
    |   |vm-1||vm-2||vm-3|  <-- internal only          |
    |   +----++----++----+                             |
    |                                                  |
    +--------------------------------------------------+

    State: gs://tfstate-project-8888321c-.../environments/learning/

## Repository Structure

    .
    |-- bootstrap.sh                          # Creates SA, bucket, key, .env
    |-- .gitignore
    |-- .pre-commit-config.yaml               # Auto-checks before every commit
    |-- .tflint.hcl                           # Terraform linter rules
    |-- .terraform-version                    # Pinned Terraform version (1.9.5)
    |
    |-- config/                               # Single Source of Truth
    |   |-- general.json                      # Project defaults (region, OS, SSH port)
    |   |-- networks.json                     # VPC networks and subnets
    |   |-- firewall.json                     # Firewall rules
    |   |-- vms.json                          # VM instances
    |   |-- schemas/                          # JSON Schema validation
    |       |-- general.schema.json
    |       |-- networks.schema.json
    |       |-- firewall.schema.json
    |       |-- vms.schema.json
    |
    |-- infrastructure/
    |   |-- modules/                          # Reusable Terraform modules
    |   |   |-- network/                      # Creates VPC + subnets
    |   |   |-- firewall/                     # Creates one firewall rule
    |   |   |-- vm/                           # Creates one VM
    |   |
    |   |-- environments/
    |       |-- learning/                     # Entry point for terraform commands
    |           |-- backend.tf                # Remote state in GCS
    |           |-- versions.tf               # Terraform and provider versions
    |           |-- providers.tf              # Google provider config
    |           |-- variables.tf              # Input variables (SSH key)
    |           |-- locals.tf                 # Reads JSON config files
    |           |-- main.tf                   # Calls modules with JSON data
    |           |-- outputs.tf                # Outputs after apply
    |
    |-- docs/
        |-- SERVICE_ACCOUNT.md                # SA permissions
        |-- STATE.md                          # Remote state documentation
        |-- JUMP_HOST.md                      # Jump host architecture and SSH access

## How It Works

All infrastructure is described in JSON files under `config/`.
Terraform reads these files and passes the data to reusable modules.
To add a new VM — add a block to `config/vms.json` and run `terraform apply`.
No `.tf` files need to be changed.

### Override Logic

Each VM uses defaults from `general.json`. Any parameter can be overridden
per VM in `vms.json`:

    "vm-5-worker": {
      "network": "terraform-network",
      "subnet": "terraform-network-subnet",
      "machine_type": "e2-small",         <- overrides default e2-micro
      "disk_size_gb": 20,                 <- overrides default 10
      "assign_public_ip": false,
      "tags": ["internal-vm", "terraform-managed"],
      "labels": { "role": "worker" }
    }

## Prerequisites

- Google Cloud SDK (gcloud)
- Terraform >= 1.5.0
- GCP project with billing enabled
- pre-commit, tflint, tfsec, terraform-docs

        brew install pre-commit tflint tfsec terraform-docs jq

## Quick Start

1. Run the bootstrap script:

        ./bootstrap.sh

2. Generate SSH key pair:

        ssh-keygen -t ed25519 -f ~/.ssh/gcp_jump -C "terraform" -N ""

3. Load environment variables:

        source .env

4. Go to the environment directory:

        cd infrastructure/environments/learning

5. Initialize Terraform:

        terraform init

6. Review the plan:

        terraform plan

7. Apply:

        terraform apply

8. Connect to jump host (SSH command is shown in outputs):

        ssh-add ~/.ssh/gcp_jump
        ssh -A -i ~/.ssh/gcp_jump -p 47832 terraform@JUMP_HOST_IP

9. From jump host, connect to internal VMs:

        ssh -p 47832 terraform@INTERNAL_VM_IP

10. Destroy when done:

        terraform destroy

## Security

- `sa-key.json` and `.env` are excluded from Git
- State stored in versioned, access-controlled GCS bucket with state locking
- Service Account follows least privilege principle
- SSH on non-default port 47832 (configured via startup script)
- Root login disabled, password authentication disabled
- Jump host accepts SSH only from a specific trusted IP
- Internal VMs have no public IP
- SSH agent forwarding used — no private keys stored on jump host
- JSON Schema validates config files in VS Code before terraform runs
- pre-commit hooks run fmt, validate, tflint, tfsec before every commit

## Documentation

- [Service Account Permissions](docs/SERVICE_ACCOUNT.md)
- [Terraform Remote State](docs/STATE.md)
- [Jump Host Architecture](docs/JUMP_HOST.md)