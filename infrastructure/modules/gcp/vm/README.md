# vm

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
| [google_compute_instance.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_instance) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_assign_public_ip"></a> [assign\_public\_ip](#input\_assign\_public\_ip) | Whether to assign a public IP to the VM | `bool` | `false` | no |
| <a name="input_disk_size_gb"></a> [disk\_size\_gb](#input\_disk\_size\_gb) | Boot disk size in GB | `number` | `10` | no |
| <a name="input_disk_type"></a> [disk\_type](#input\_disk\_type) | Boot disk type | `string` | `"pd-standard"` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment label | `string` | `"learning"` | no |
| <a name="input_labels"></a> [labels](#input\_labels) | Labels to apply to the VM | `map(string)` | `{}` | no |
| <a name="input_machine_type"></a> [machine\_type](#input\_machine\_type) | Machine type for the VM | `string` | `"e2-micro"` | no |
| <a name="input_name"></a> [name](#input\_name) | VM instance name | `string` | n/a | yes |
| <a name="input_network_self_link"></a> [network\_self\_link](#input\_network\_self\_link) | Self-link of the VPC network | `string` | n/a | yes |
| <a name="input_os_image"></a> [os\_image](#input\_os\_image) | Boot disk OS image | `string` | `"debian-cloud/debian-12"` | no |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | GCP Project ID | `string` | n/a | yes |
| <a name="input_ssh_port"></a> [ssh\_port](#input\_ssh\_port) | SSH port to configure on the VM | `number` | `47832` | no |
| <a name="input_ssh_public_key"></a> [ssh\_public\_key](#input\_ssh\_public\_key) | SSH public key content for VM access | `string` | n/a | yes |
| <a name="input_ssh_user"></a> [ssh\_user](#input\_ssh\_user) | SSH username to create on the VM | `string` | `"terraform"` | no |
| <a name="input_subnet_self_link"></a> [subnet\_self\_link](#input\_subnet\_self\_link) | Self-link of the subnet | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Network tags for firewall rules | `list(string)` | `[]` | no |
| <a name="input_zone"></a> [zone](#input\_zone) | GCP zone | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_external_ip"></a> [external\_ip](#output\_external\_ip) | External IP of the VM (null if not assigned) |
| <a name="output_instance_id"></a> [instance\_id](#output\_instance\_id) | ID of the VM instance |
| <a name="output_instance_name"></a> [instance\_name](#output\_instance\_name) | Name of the VM instance |
| <a name="output_internal_ip"></a> [internal\_ip](#output\_internal\_ip) | Internal IP of the VM |
| <a name="output_self_link"></a> [self\_link](#output\_self\_link) | Self-link of the VM instance |
| <a name="output_zone"></a> [zone](#output\_zone) | Zone of the VM instance |
<!-- END OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
