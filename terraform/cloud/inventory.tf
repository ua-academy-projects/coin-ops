# inventory.tf

resource "local_file" "ansible_inventory" {
  filename = "${path.module}/../../ansible/inventory.yml"
  content  = local.inventory_content
}
