# terraform/cloud

This Terraform root provisions the existing cloud VM infrastructure. For the
current Azure work, it also uses the Azure Blob backend created by
`bootstrap/azure-bootstrap.sh`.

## Azure local workflow

Run bootstrap first from the repository root:

```bash
./bootstrap/azure-bootstrap.sh
```

Bootstrap creates three local files:

- `bootstrap/backend.azure.hcl`
- `bootstrap/azure.env`
- `terraform/cloud/azure.auto.tfvars.json`

These files are ignored by Git because they contain local environment values.

Then run Terraform:

```bash
source bootstrap/azure.env
terraform -chdir=terraform/cloud init -backend-config=../../bootstrap/backend.azure.hcl -reconfigure
terraform -chdir=terraform/cloud plan -lock-timeout=30s
```

`azure.auto.tfvars.json` is loaded automatically by Terraform, so the Azure
resource group, Key Vault, location, and config name do not need to be repeated
as `-var` arguments.

To use another config file, rerun bootstrap with `TF_CONFIG_NAME`:

```bash
TF_CONFIG_NAME=vm ./bootstrap/azure-bootstrap.sh
```

For the AKS platform config:

```bash
TF_CONFIG_NAME=aks ./bootstrap/azure-bootstrap.sh
source bootstrap/azure.env
terraform -chdir=terraform/cloud init -backend-config=../../bootstrap/backend.azure.hcl -reconfigure
terraform -chdir=terraform/cloud plan -lock-timeout=30s
```
