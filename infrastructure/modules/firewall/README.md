# Module: firewall

Creates a single GCP firewall rule. Use with `for_each` to create multiple rules.

## Usage

```hcl
module "firewall_ssh" {
  source            = "../../modules/firewall"
  project_id        = "your-project-id"
  name              = "allow-ssh-jump"
  network_self_link = module.network.network_self_link
  protocol          = "tcp"
  ports             = ["47832"]
  source_ranges     = ["YOUR_IP/32"]
  target_tags       = ["jump-host"]
  description       = "Allow SSH to jump host from trusted IP only"
}
```

## Inputs

<!-- terraform-docs will auto-generate this section -->

## Outputs

<!-- terraform-docs will auto-generate this section -->