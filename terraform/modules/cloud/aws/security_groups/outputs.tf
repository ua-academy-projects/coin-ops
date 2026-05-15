output "sg_ids" {
  value = { for role, sg in aws_security_group.sg : role => sg.id }
}
