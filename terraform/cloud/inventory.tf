# inventory.tf

resource "local_file" "ansible_inventory" {
  filename = "${path.module}/../../ansible/inventory"
  content  = local.inventory_content
}
