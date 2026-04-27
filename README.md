# GCP Terraform Bootstrap

Bootstrap a GCP project for Terraform using a Service Account and remote state in GCS.

## Architecture

    Local Machine (Mac)
        |
        | ssh -A (agent forwarding)
        v
    +-----------------------------------------------+
    |           VPC: terraform-network               |
    |           Subnet: 10.0.0.0/24                  |
    |                                                |
    |   +------------------+                         |
    |   |  vm-4-jump       | <-- public IP (SSH)     |
    |   +--------+---------+                         |
    |            |                                   |
    |      +-----+-----+                             |
    |      v     v     v                             |
    |   +-----+-----+-----+                         |
    |   |vm-1 |vm-2 |vm-3 |  <-- internal only      |
    |   +-----+-----+-----+                         |
    |                                                |
    +-----------------------------------------------+
    
    State: gs://tfstate-project-8888321c-.../terraform/state/

## Repository Structure

    .
    |-- bootstrap.sh                 # Creates SA, bucket, key, .env
    |-- .gitignore
    |-- terraform/
    |   |-- backend.tf               # Remote state in GCS
    |   |-- provider.tf              # Google provider config
    |   |-- variables.tf             # Variable definitions with validation
    |   |-- terraform.tfvars.example # Template for variable values
    |   |-- main.tf                  # VPC, subnet, firewall, 4 VMs
    |   |-- outputs.tf               # Output values after apply
    |-- docs/
    |   |-- SERVICE_ACCOUNT.md       # SA permissions documentation
    |   |-- STATE.md                 # Remote state documentation
    |   |-- JUMP_HOST.md             # Jump host architecture and SSH access

## Prerequisites

- Google Cloud SDK (gcloud)
- Terraform >= 1.5.0
- GCP project with billing enabled
- SSH key pair for VM access

## Quick Start

1. Run the bootstrap script:

        ./bootstrap.sh

2. Generate SSH key:

        ssh-keygen -t ed25519 -f ~/.ssh/gcp_jump -C "terraform" -N ""

3. Load environment variables:

        source .env

4. Create terraform.tfvars from the example:

        cp terraform/terraform.tfvars.example terraform/terraform.tfvars
        # Edit terraform.tfvars with your values

5. Initialize and apply:

        cd terraform
        terraform init
        terraform plan
        terraform apply

6. Connect to jump host:

        ssh-add ~/.ssh/gcp_jump
        ssh -A -i ~/.ssh/gcp_jump terraform@<JUMP_HOST_EXTERNAL_IP>

7. From jump host, connect to internal VMs:

        ssh terraform@<INTERNAL_VM_IP>

8. Destroy when done:

        terraform destroy

## Security

- `sa-key.json` and `.env` are excluded from Git
- State is stored remotely in a versioned, access-controlled GCS bucket
- Service Account follows the principle of least privilege
- Jump host accepts SSH only from a specific trusted IP
- Internal VMs have no public IP
- SSH agent forwarding used instead of storing keys on jump host

## Documentation

- [Service Account Permissions](docs/SERVICE_ACCOUNT.md)
- [Terraform Remote State](docs/STATE.md)
- [Jump Host Architecture](docs/JUMP_HOST.md)
