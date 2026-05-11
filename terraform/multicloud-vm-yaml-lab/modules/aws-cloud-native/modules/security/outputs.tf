output "security_group_ids" {
  value = {
    bastion = aws_security_group.bastion.id
    lb      = aws_security_group.lb.id
    app     = aws_security_group.app.id
    db      = aws_security_group.db.id
  }
}
