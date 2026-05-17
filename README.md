# Multi-Cloud Terraform Bootstrap

This project is a learning Terraform setup that can deploy the same logical environment to GCP, AWS, or Azure. One Terraform environment is used for all clouds, and the target cloud is selected with a single variable.

## Workflow

Run all commands from the repository root.

Set the SSH public key for VM access:

```bash
export TF_VAR_ssh_public_key="$(cat ~/.ssh/gcp_jump.pub)"
```

Azure additionally requires Service Principal credentials in the environment:

```bash
export ARM_CLIENT_ID="<service-principal-app-id>"
export ARM_CLIENT_SECRET="$(security find-generic-password -a terraform-sp -s azure-arm-secret -w)"
export ARM_TENANT_ID="<tenant-id>"
export ARM_SUBSCRIPTION_ID="<subscription-id>"
```

Deploy to a cloud (replace `gcp` with `aws` or `azure`):

```bash
./deploy.sh gcp init
./deploy.sh gcp plan
./deploy.sh gcp apply
```

Destroy:

```bash
./deploy.sh gcp destroy
```

## Repository Structure

```text
.
|-- bootstrap/
|   |-- gcp/bootstrap.sh
|   |-- aws/bootstrap.sh
|   `-- azure/bootstrap.sh
|-- config/
|   |-- general.json
|   |-- networks.json
|   |-- firewall.json
|   |-- vms.json
|   |-- lookups.json
|   `-- schemas/
|       |-- general.schema.json
|       |-- networks.schema.json
|       |-- firewall.schema.json
|       |-- vms.schema.json
|       `-- lookups.schema.json
|-- infrastructure/
|   |-- modules/
|   |   |-- gcp/
|   |   |   |-- network/
|   |   |   |-- firewall/
|   |   |   `-- vm/
|   |   |-- aws/
|   |   |   |-- network/
|   |   |   |-- firewall/
|   |   |   `-- vm/
|   |   `-- azure/
|   |       |-- network/
|   |       |-- firewall/
|   |       `-- vm/
|   `-- environments/
|       `-- learning/
|           |-- versions.tf
|           |-- providers.tf
|           |-- variables.tf
|           |-- locals.tf
|           |-- main.tf
|           |-- outputs.tf
|           |-- backend.tf
|           `-- backends/
|               |-- gcp.hcl
|               |-- aws.hcl
|               |-- azure.hcl
|               |-- backend-gcp.tf.template
|               |-- backend-aws.tf.template
|               `-- backend-azure.tf.template
`-- deploy.sh
```

## How Cloud Switching Works

`config/*.json` contains cloud-neutral resource definitions. Terraform filters those resources by `var.cloud`, and `main.tf` uses `count` or empty `for_each` maps so only the selected cloud creates resources.

```bash
terraform apply -var="cloud=gcp"
terraform apply -var="cloud=aws"
terraform apply -var="cloud=azure"
```

The backend type cannot be dynamic in Terraform, so `deploy.sh` copies the matching backend template into `infrastructure/environments/learning/backend.tf` before running Terraform.

## Per-VM Provider Override

By default every VM is created in the cloud passed via `var.cloud`. A VM can be pinned to a specific cloud by adding an optional `provider` field in `config/vms.json`:

```json
"vm-1": {
  "provider": "azure",
  "network": "terraform-network",
  "subnet": "terraform-network-subnet"
}
```

Rules:

- VM **without** a `provider` field is created in whatever cloud `var.cloud` selects.
- VM **with** a `provider` field is created only when `var.cloud` matches that provider; otherwise it is skipped for that run.

This logic lives in `infrastructure/environments/learning/locals.tf`, where each VM's target cloud is resolved with `lookup(vm, "provider", var.cloud)` and the VM map is filtered accordingly.

## State Backends

Each cloud stores Terraform state in its own backend:

```text
GCP    gs://tfstate-project-8888321c-54a9-4dac-86d/environments/learning/
AWS    s3://tfstate-kazachuk-aws-learning/environments/learning/terraform.tfstate
Azure  Storage Account tfstatekazachukazure, container tfstate, key environments/learning/terraform.tfstate
```

AWS state locking uses the DynamoDB table `terraform-state-lock`. Azure state locking is handled natively through blob leases. GCP uses native object-based locking.

## Authentication

- **GCP** — service account key flow with `sa-key.json`.
- **AWS** — credentials configured by `aws configure`.
- **Azure** — Service Principal credentials supplied through the `ARM_*` environment variables shown in the Workflow section.

## Configuration

`config/lookups.json` maps abstract values such as `small`, `debian-12`, and `standard` to provider-specific machine types, images, and disk types for all three clouds. This keeps `general.json` and `vms.json` cloud-neutral.