# Deprecated

This directory holds infrastructure and configuration that is no longer used
on `dev` but is kept in tree for reference.

| Path | What it is | Why deprecated |
| --- | --- | --- |
| `hyperv-lab/terraform/` | Terraform that provisions 3 Ubuntu VMs in Hyper-V on a Windows host (uses the `taliesins/hyperv` provider). The original local lab setup. | Active development now targets GCP. VM provisioning for GCP lives in the separate `gcp-terraform-bootstrap` repo. The k3s lab is created the same way. |
| `hyperv-lab/ansible-inventory` | Static Ansible inventory pointing at `softserve-node-01..03` on `172.31.1.0/24`. | Same as above. Current inventories live under `ansible/inventories/gcp-vm/` and `ansible/inventories/gcp-k3s/`. |

Nothing here is wired into CI or the active playbooks. Treat it as a frozen
snapshot. If something needs to come back to life, expect to update paths and
provider versions before it works again.
