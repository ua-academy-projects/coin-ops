moved {
  from = aws_vpc.this
  to   = module.network.aws_vpc.this
}

moved {
  from = aws_internet_gateway.this
  to   = module.network.aws_internet_gateway.this
}

moved {
  from = aws_subnet.public
  to   = module.network.aws_subnet.public
}

moved {
  from = aws_subnet.private
  to   = module.network.aws_subnet.private
}

moved {
  from = aws_route_table.public
  to   = module.network.aws_route_table.public
}

moved {
  from = aws_route.public_internet
  to   = module.network.aws_route.public_internet
}

moved {
  from = aws_route_table_association.public
  to   = module.network.aws_route_table_association.public
}

moved {
  from = aws_eip.nat
  to   = module.network.aws_eip.nat
}

moved {
  from = aws_nat_gateway.this
  to   = module.network.aws_nat_gateway.this
}

moved {
  from = aws_route_table.private
  to   = module.network.aws_route_table.private
}

moved {
  from = aws_route.private_nat
  to   = module.network.aws_route.private_nat
}

moved {
  from = aws_route_table_association.private
  to   = module.network.aws_route_table_association.private
}

moved {
  from = aws_security_group.bastion
  to   = module.security.aws_security_group.bastion
}

moved {
  from = aws_security_group.lb
  to   = module.security.aws_security_group.lb
}

moved {
  from = aws_security_group.app
  to   = module.security.aws_security_group.app
}

moved {
  from = aws_security_group.db
  to   = module.security.aws_security_group.db
}

moved {
  from = aws_key_pair.lab
  to   = module.compute.aws_key_pair.lab
}

moved {
  from = aws_instance.bastion
  to   = module.compute.aws_instance.bastion
}

moved {
  from = aws_instance.app
  to   = module.compute.aws_instance.app
}

moved {
  from = aws_instance.db
  to   = module.compute.aws_instance.db
}

moved {
  from = aws_lb.app
  to   = module.load_balancer.aws_lb.app
}

moved {
  from = aws_lb_target_group.app
  to   = module.load_balancer.aws_lb_target_group.app
}

moved {
  from = aws_lb_target_group_attachment.app
  to   = module.load_balancer.aws_lb_target_group_attachment.app
}

moved {
  from = aws_acm_certificate.app
  to   = module.certificate_dns.aws_acm_certificate.app
}

moved {
  from = cloudflare_dns_record.cert_validation
  to   = module.certificate_dns.cloudflare_dns_record.cert_validation
}

moved {
  from = aws_acm_certificate_validation.app
  to   = module.certificate_dns.aws_acm_certificate_validation.app
}

moved {
  from = aws_lb_listener.https
  to   = module.certificate_dns.aws_lb_listener.https
}

moved {
  from = aws_lb_listener.http_redirect
  to   = module.certificate_dns.aws_lb_listener.http_redirect
}

moved {
  from = cloudflare_dns_record.app
  to   = module.certificate_dns.cloudflare_dns_record.app
}
