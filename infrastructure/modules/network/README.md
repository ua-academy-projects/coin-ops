# Module: network

Creates a GCP VPC network with one or more subnets.

## Usage

```hcl
module "network" {
  source     = "../../modules/network"
  project_id = "your-project-id"
  name       = "my-network"

  subnets = {
    "my-subnet" = {
      cidr   = "10.0.0.0/24"
      region = "us-central1"
    }
  }
}
```

## Inputs

<!-- terraform-docs will auto-generate this section -->

## Outputs

<!-- terraform-docs will auto-generate this section -->