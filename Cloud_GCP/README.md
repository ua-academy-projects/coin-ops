# Cloud GCP — Jump Host Infrastructure


## Task

Deploy 4 VMs on GCP via Terraform:
- 3 internal VMs (no public IP)
- 1 jump host (public + internal IP, port 22 only)

SSH to internal VMs only through the jump host.

## Structure

```
Cloud_GCP/
├── docs/
│   ├── 00-README-task1.md                 # Bootstrap & service account explanation
│   ├── 01-bootstrap-service-account.md    # GCP project setup, IAM, service account
│   └── 02-terraform-jump-host.md          # Terraform, jump host, firewall, SSH flow
├── terraform/
│   ├── main.tf                            # VMs, network, firewall rules
│   ├── outputs.tf                         # IPs output
│   ├── backend.tf                         # Remote state in GCS bucket
│   ├── provider.tf                        # GCP provider config
│   ├── variables.tf                       # Variable declarations
│   └── terraform.tfvars                   # gitignored — values for variables
├── bootstrap.sh                           # One-time GCP project setup script
└── key.json                               # gitignored — service account credentials
```

## Docs

- [Bootstrap & Service Account](docs/01-bootstrap-service-account.md)
- [Terraform Jump Host Architecture](docs/02-terraform-jump-host.md)
