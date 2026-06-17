# Architecture

```mermaid
flowchart TD
  Dev[Engineer workstation] -->|./bootstrap.sh| AzureCLI[Azure CLI + Terraform]
  AzureCLI --> State[Azure Storage remote tfstate]
  AzureCLI --> RG[Platform Resource Group]
  RG --> VNet[Virtual Network]
  RG --> ACR[Azure Container Registry]
  RG --> AKS[AKS Cluster]
  AKS --> JenkinsNS[Jenkins Namespace]
  JenkinsNS --> Jenkins[Jenkins via Helm]
  Jenkins -->|Build / Test / Push| ACR
  Jenkins -->|Helm upgrade| AppNS[Application Namespace]
  AppNS --> App[Application Pods]
  App --> Service[ClusterIP Service]
  Service --> Ingress[Ingress]
```

## Component Explanation

- **bootstrap.sh**: local entrypoint that prepares backend, credentials, and Terraform execution.
- **Azure Storage backend**: remote state store for Terraform.
- **AKS**: target runtime cluster for Jenkins and the sample application.
- **ACR**: image registry for the CI/CD pipeline.
- **Jenkins**: CI/CD orchestrator running inside AKS.
- **Helm app chart**: application delivery unit for dev/prod values.

