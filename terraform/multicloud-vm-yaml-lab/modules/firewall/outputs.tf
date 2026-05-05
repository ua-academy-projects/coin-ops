output "rule_names" {
  value = concat(
    [
      google_compute_firewall.ssh_to_bastion.name,
      google_compute_firewall.ssh_from_bastion_to_private.name,
    ],
    [for rule in google_compute_firewall.icmp_from_bastion_to_private : rule.name]
  )
}
