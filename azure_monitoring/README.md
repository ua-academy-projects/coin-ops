# Azure Monitoring Lab

Minimal Terraform for a single Ubuntu VM in Azure plus basic Azure Monitor alerting. The goal is to have a simple lab where you can practice:

- Azure Monitor metrics
- metric alerts
- action groups
- CPU load testing on a VM

## Files

- `providers.tf` - Terraform and provider requirements
- `variables.tf` - input variables
- `main.tf` - existing resource group lookup, network, NSG, public IP, NIC, Linux VM, action group, metric alert
- `outputs.tf` - VM IP, SSH command, and alert names
- `terraform.tfvars.example` - example variable file
- `backend.hcl.example` - example Azure Storage backend config for remote state

## Usage

```bash
az login
cd /home/valentyn/Devops/git.repo/coin-ops/coin-ops/azure_monitoring
cp terraform.tfvars.example terraform.tfvars
cp backend.hcl.example backend.hcl
terraform init -backend-config=backend.hcl
terraform apply
```

Terraform reads the SSH public key from `~/.ssh/id_rsa.pub` by default. If your key is stored elsewhere, change `ssh_public_key_path` in `terraform.tfvars`.

## Remote State In Azure

This configuration is prepared to store `terraform.tfstate` in Azure Storage through the `azurerm` backend.

Important:

- the backend storage account and blob container must already exist before `terraform init`
- backend settings are stored in `backend.hcl`
- `backend.hcl` is ignored by git

Example `backend.hcl`:

```hcl
resource_group_name  = "navigator"
storage_account_name = "navtfstate001"
container_name       = "tfstate"
key                  = "azure_monitoring/terraform.tfstate"
use_azuread_auth     = true
```

Example bootstrap commands for the backend storage:

```bash
az storage account create \
  --name navtfstate001 \
  --resource-group navigator \
  --location westeurope \
  --sku Standard_LRS \
  --kind StorageV2

az storage container create \
  --name tfstate \
  --account-name navtfstate001 \
  --auth-mode login
```

If you already have a local `terraform.tfstate`, migrate it into Azure like this:

```bash
terraform init -migrate-state -backend-config=backend.hcl
```

After migration, Terraform will read and write state in Azure Storage instead of the local `terraform.tfstate` file.

This configuration expects that the Azure resource group already exists. By default it uses:

- `navigator`

Example `terraform.tfvars`:

```hcl
resource_group_name = "navigator"
location            = "westeurope"
prefix              = "monitorlab"
vm_name             = "monitor-vm"
admin_username      = "azureuser"
vm_size             = "Standard_B2s"
allowed_ssh_cidr    = "0.0.0.0/0"
ssh_public_key_path = "~/.ssh/id_rsa.pub"
alert_email         = "val.don.ua@gmail.com"
cpu_alert_threshold = 45
```

Terraform creates:

- a virtual network, subnet, NSG, public IP, NIC, and Ubuntu VM
- an Azure Monitor action group with an email receiver
- a metric alert for `Percentage CPU`

Defaults:

- alert email: `val.don.ua@gmail.com`
- CPU threshold: `45%`
- alert severity: `3`
- metric aggregation: `Average`
- evaluation frequency: `1 minute`
- alert window: `5 minutes`

After apply:

```bash
terraform output vm_public_ip
terraform output ssh_command
terraform output action_group_name
terraform output cpu_alert_name
```

## Testing The Alert

Connect to the VM and generate CPU load:

```bash
ssh azureuser@<public-ip>
sudo apt-get update
sudo apt-get install -y stress
stress --cpu 2 --timeout 300
```

What should happen:

- Azure Monitor collects the VM metric `Percentage CPU`
- if average CPU stays above `45%` over the `5 minute` window, the metric alert fires
- the action group sends a notification email to `val.don.ua@gmail.com`

You can verify the result in:

- Azure Portal -> Virtual Machine -> `Metrics`
- Azure Portal -> `Monitor` -> `Alerts`
- your email inbox for the action group notification

## Destroy

```bash
terraform destroy
```
