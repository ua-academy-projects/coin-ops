# locals.tf

locals {
  inventory_hosts = {
    history = "coinops-history"
    proxy   = "coinops-proxy"
    ui      = "coinops-ui"
    bastion = "coinops-bastion"
    nat     = "coinops-nat"
  }

  private_ips = var.cloud == "gcp" ? try(module.gcp_instances[0].private_ips, {}) : try(module.aws_instances[0].private_ips, {})
  public_ips  = var.cloud == "gcp" ? try(module.gcp_instances[0].public_ips, {}) : try(module.aws_instances[0].public_ips, {})

  inventory_content = <<-INV
    [history]
    ${local.inventory_hosts.history} ansible_host=${local.private_ips[local.inventory_hosts.history]} private_ip=${local.private_ips[local.inventory_hosts.history]}

    [proxy]
    ${local.inventory_hosts.proxy} ansible_host=${local.private_ips[local.inventory_hosts.proxy]} private_ip=${local.private_ips[local.inventory_hosts.proxy]}

    [ui]
    ${local.inventory_hosts.ui} ansible_host=${local.private_ips[local.inventory_hosts.ui]} private_ip=${local.private_ips[local.inventory_hosts.ui]}

    [bastion]
    ${local.inventory_hosts.bastion} ansible_host=${local.public_ips[local.inventory_hosts.bastion]} private_ip=${local.private_ips[local.inventory_hosts.bastion]}

    [nat]
    ${local.inventory_hosts.nat} ansible_host=${local.private_ips[local.inventory_hosts.nat]} private_ip=${local.private_ips[local.inventory_hosts.nat]}
  INV
}
