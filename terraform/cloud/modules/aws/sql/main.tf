# main.tf

resource "aws_db_subnet_group" "this" {
  name       = "${local.instance.identifier}-subnets"
  subnet_ids = values(var.private_subnet_ids)
}

resource "aws_security_group" "this" {
  name   = "${local.instance.identifier}-db"
  vpc_id = var.network_id
}

resource "aws_db_instance" "this" {
  identifier              = local.instance.identifier
  engine                  = local.instance.engine
  engine_version          = local.instance.engine_version
  instance_class          = local.instance.instance_class
  allocated_storage       = local.instance.allocated_storage
  storage_type            = local.instance.storage_type
  multi_az                = local.instance.multi_az
  db_name                 = local.instance.database_name
  username                = local.instance.username
  password                = data.aws_secretsmanager_secret_version.db_password.secret_string
  db_subnet_group_name    = aws_db_subnet_group.this.name
  vpc_security_group_ids  = [aws_security_group.this.id]
  publicly_accessible     = false
  skip_final_snapshot     = true
  deletion_protection     = local.instance.deletion_protection
  backup_retention_period = local.instance.backup_retention
}
