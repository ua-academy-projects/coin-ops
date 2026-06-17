# Azure AKS Jenkins Platform

This project provisions a production-like AKS + ACR + Jenkins platform on Microsoft Azure with a single command:

```bash
./bootstrap.sh
```

The scaffold is intentionally isolated from the rest of the repository so it can be used as a standalone end-to-end DevOps portfolio project.

## Step-by-Step Delivery

### Step 1. Bootstrap

`bootstrap.sh` performs the full local bootstrap flow:

- checks required tools: `az`, `terraform`, `kubectl`, `helm`, `docker`, `git`
- ensures Azure login
- selects the target subscription
- creates or reuses the remote state resource group, storage account, and blob container
- creates or reuses a Terraform service principal
- assigns required Azure RBAC permissions
- exports `ARM_*` variables
- generates environment tfvars when missing
- runs `terraform init` and `terraform apply`

### Step 2. Terraform backend

Terraform uses the Azure Storage backend (`azurerm`) with backend config generated into `.generated/backend.hcl`.

### Step 3. Azure infrastructure

Terraform provisions:

- platform resource group
- virtual network
- AKS subnet
- application subnet
- Azure Container Registry
- Azure Kubernetes Service

### Step 4. AKS and ACR

AKS is provisioned with:

- managed identity
- Azure RBAC enabled
- OIDC issuer enabled
- Workload Identity enabled

ACR is provisioned separately and attached to the AKS kubelet identity using `AcrPull`.

### Step 5. Jenkins installation

Terraform uses the `helm` provider to install Jenkins into AKS:

- namespace created automatically
- persistent storage enabled
- service type `LoadBalancer`
- admin credentials created through a Kubernetes secret
- required plugins installed

### Step 6. Jenkins pipeline

`Jenkinsfile` implements:

1. checkout
2. build
3. test
4. push image to ACR
5. deploy with Helm
6. verify rollout
7. rollback on failure

### Step 7. Application deployment

The application Helm chart lives in `helm/app` and includes:

- Deployment
- Service
- Ingress
- ConfigMap
- Secret
- environment-specific values files

### Step 8. Hardening and production improvements

See [docs/hardening.md](docs/hardening.md) for production follow-up work.

## Repository Structure

```text
azure-aks-jenkins/
├── bootstrap.sh
├── Jenkinsfile
├── environments/
│   ├── dev/
│   │   └── terraform.tfvars.example
│   └── prod/
│       └── terraform.tfvars.example
├── helm/
│   ├── app/
│   └── jenkins/
├── k8s/
├── modules/
│   ├── acr/
│   ├── aks/
│   ├── jenkins/
│   ├── network/
│   ├── rbac/
│   └── resource-group/
├── terraform/
└── docs/
```

## Execution

### 1. Set the target subscription

```bash
export AZURE_SUBSCRIPTION_ID="<subscription-id>"
```

Optional overrides:

```bash
export ENVIRONMENT=dev
export AZURE_LOCATION=westeurope
export PROJECT_NAME=azure-aks-jenkins
export NAME_PREFIX=azplat
```

### 2. Run bootstrap

```bash
cd azure-aks-jenkins
chmod +x bootstrap.sh
./bootstrap.sh
```

### 3. Read outputs

```bash
terraform -chdir=terraform output
```

## Key Design Decisions

- **Dedicated project directory**: avoids collisions with the repository's existing VM-based infrastructure.
- **Azure Storage backend**: production-like Terraform state storage with RBAC and blob locking semantics.
- **Terraform service principal**: usable from a local shell while still keeping infra changes scoped and reproducible.
- **Managed identity for AKS**: avoids static pull credentials for the cluster.
- **Helm-based Jenkins installation**: keeps Jenkins lifecycle under Terraform and Kubernetes.
- **Scoped Kubernetes RBAC for Jenkins**: Jenkins can deploy applications into the application namespace without needing cluster-admin.
- **Separate application chart**: keeps CI/CD deploy logic independent from infrastructure modules.

## Files to Review First

- [bootstrap.sh](bootstrap.sh)
- [terraform/main.tf](terraform/main.tf)
- [modules/aks/main.tf](modules/aks/main.tf)
- [modules/jenkins/main.tf](modules/jenkins/main.tf)
- [Jenkinsfile](Jenkinsfile)
- [docs/architecture.md](docs/architecture.md)

