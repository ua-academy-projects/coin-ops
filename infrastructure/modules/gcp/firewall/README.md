# firewall

<!-- BEGINNING OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.5.0 |
| <a name="requirement_google"></a> [google](#requirement\_google) | >= 5.0, < 6.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_google"></a> [google](#provider\_google) | 5.45.2 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [google_compute_firewall.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_firewall) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_description"></a> [description](#input\_description) | Human-readable description of the rule | `string` | `""` | no |
| <a name="input_name"></a> [name](#input\_name) | Firewall rule name | `string` | n/a | yes |
| <a name="input_network_self_link"></a> [network\_self\_link](#input\_network\_self\_link) | Self-link of the VPC network | `string` | n/a | yes |
| <a name="input_ports"></a> [ports](#input\_ports) | List of ports or port ranges (e.g. 22, 8080, 0-65535) | `list(string)` | `[]` | no |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | GCP Project ID | `string` | n/a | yes |
| <a name="input_protocol"></a> [protocol](#input\_protocol) | Protocol for single-protocol rules (tcp, udp, icmp, all) | `string` | `null` | no |
| <a name="input_protocols"></a> [protocols](#input\_protocols) | List of protocols for multi-protocol rules | `list(string)` | `[]` | no |
| <a name="input_source_ranges"></a> [source\_ranges](#input\_source\_ranges) | Source CIDR ranges (e.g. 10.0.0.0/24, 0.0.0.0/0) | `list(string)` | `[]` | no |
| <a name="input_source_tags"></a> [source\_tags](#input\_source\_tags) | Source network tags | `list(string)` | `[]` | no |
| <a name="input_target_tags"></a> [target\_tags](#input\_target\_tags) | Target network tags this rule applies to | `list(string)` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_firewall_rule_name"></a> [firewall\_rule\_name](#output\_firewall\_rule\_name) | Name of the created firewall rule |
| <a name="output_firewall_rule_self_link"></a> [firewall\_rule\_self\_link](#output\_firewall\_rule\_self\_link) | Self-link of the created firewall rule |
<!-- END OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
