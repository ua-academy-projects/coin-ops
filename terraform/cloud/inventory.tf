# inventory.tf

resource "local_file" "ansible_inventory" {
  filename = "${path.module}/../../ansible/inventory"
  content  = local.inventory_content

  lifecycle {
    precondition {
      condition     = length(local.network_clouds_with_multiple_networks) == 0
      error_message = "Only one network per cloud is supported for now."
    }

    precondition {
      condition     = length(local.workload_clouds_without_network) == 0
      error_message = "Each workload cloud must have exactly one network assigned to it."
    }

    precondition {
      condition     = length(local.invalid_workload_subnet_refs) == 0
      error_message = "Each workload subnet must exist in that workload cloud's network."
    }
  }
}
