resource "aws_db_instance" "postgres" {
  count = var.cloud_provider == "aws" ? 1 : 0

  identifier             = "coinops-postgres"
  engine                 = "postgres"
  engine_version         = var.db_engine_version
  instance_class         = var.db_instance_class
  allocated_storage      = var.db_allocated_storage
  storage_type           = var.db_storage_type
  db_name                = var.db_name
  username               = var.db_username
  password               = random_password.db_password.result
  vpc_security_group_ids = var.security_group_ids
  db_subnet_group_name   = aws_db_subnet_group.postgres[0].name

  publicly_accessible       = false
  multi_az                  = var.multi_az
  backup_retention_period   = var.backup_retention_days
  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = false
  final_snapshot_identifier = "coinops-postgres-final-snapshot"

  tags = merge(var.common_tags, {
    Name = "coinops-postgres"
  })
}

resource "aws_db_subnet_group" "postgres" {
  count = var.cloud_provider == "aws" ? 1 : 0

  name       = "coinops-postgres-subnet-group"
  subnet_ids = var.subnet_ids

  tags = var.common_tags
}


