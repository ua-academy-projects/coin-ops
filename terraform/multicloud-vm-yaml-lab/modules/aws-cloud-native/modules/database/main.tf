locals {
  database = var.runtime.database
}

resource "aws_security_group" "database" {
  name        = "${var.name_prefix}-rds-sg"
  description = "Managed PostgreSQL access from app instances"
  vpc_id      = var.vpc_id

  ingress {
    description     = "PostgreSQL from app instances"
    from_port       = local.database.port
    to_port         = local.database.port
    protocol        = "tcp"
    security_groups = [var.app_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name_prefix}-rds-sg" }
}

resource "aws_db_subnet_group" "this" {
  name       = "${var.name_prefix}-db-subnets"
  subnet_ids = values(var.private_subnet_ids)

  tags = { Name = "${var.name_prefix}-db-subnets" }
}

resource "aws_db_instance" "this" {
  identifier              = "${var.name_prefix}-postgres"
  engine                  = "postgres"
  engine_version          = tostring(local.database.version)
  instance_class          = local.database.aws_instance_class
  allocated_storage       = local.database.storage_gb
  storage_type            = "gp3"
  db_name                 = local.database.name
  username                = local.database.user
  password                = var.db_password
  port                    = local.database.port
  publicly_accessible     = false
  db_subnet_group_name    = aws_db_subnet_group.this.name
  vpc_security_group_ids  = [aws_security_group.database.id]
  backup_retention_period = 1
  skip_final_snapshot     = true
  deletion_protection     = false
  apply_immediately       = true

  tags = { Name = "${var.name_prefix}-postgres" }
}
