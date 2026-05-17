# learning

<!-- BEGINNING OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.5.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 5.0, < 6.0 |
| <a name="requirement_google"></a> [google](#requirement\_google) | >= 5.0, < 6.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | 5.100.0 |
| <a name="provider_google"></a> [google](#provider\_google) | 5.45.2 |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_firewall_aws"></a> [firewall\_aws](#module\_firewall\_aws) | ../../modules/aws/firewall | n/a |
| <a name="module_firewall_gcp"></a> [firewall\_gcp](#module\_firewall\_gcp) | ../../modules/gcp/firewall | n/a |
| <a name="module_network_aws"></a> [network\_aws](#module\_network\_aws) | ../../modules/aws/network | n/a |
| <a name="module_network_gcp"></a> [network\_gcp](#module\_network\_gcp) | ../../modules/gcp/network | n/a |
| <a name="module_vm_aws"></a> [vm\_aws](#module\_vm\_aws) | ../../modules/aws/vm | n/a |
| <a name="module_vm_gcp"></a> [vm\_gcp](#module\_vm\_gcp) | ../../modules/gcp/vm | n/a |

## Resources

| Name | Type |
| ---- | ---- |
| [aws_key_pair.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/key_pair) | resource |
| [google_compute_project_metadata.ssh_keys](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_project_metadata) | resource |
| [google_compute_router.nat_gcp](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_router) | resource |
| [google_compute_router_nat.nat_gcp](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_router_nat) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_cloud"></a> [cloud](#input\_cloud) | Target cloud provider (gcp or aws) | `string` | n/a | yes |
| <a name="input_ssh_public_key"></a> [ssh\_public\_key](#input\_ssh\_public\_key) | SSH public key content for VM access | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_cloud"></a> [cloud](#output\_cloud) | Selected cloud provider |
| <a name="output_networks"></a> [networks](#output\_networks) | Created networks |
| <a name="output_ssh_command"></a> [ssh\_command](#output\_ssh\_command) | SSH command to connect to jump host (if exists) |
| <a name="output_vms"></a> [vms](#output\_vms) | All VM details |
<!-- END OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
