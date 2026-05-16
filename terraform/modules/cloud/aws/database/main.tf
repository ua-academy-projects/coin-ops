resource "random_id" "db_name_suffix" {
  byte_length = 4
}

resource "aws_security_group" "database" {
  name        = "${var.project_name}-db-sg"
  description = "Managed PostgreSQL access for ${var.project_name}"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.project_name}-db-sg"
    Project = var.project_name
    Cloud   = "aws"
  }
}

resource "aws_security_group_rule" "backend_to_database" {
  type                     = "ingress"
  security_group_id        = aws_security_group.database.id
  protocol                 = "tcp"
  from_port                = var.db_port
  to_port                  = var.db_port
  source_security_group_id = var.backend_security_group_id
}

resource "aws_db_subnet_group" "database" {
  name       = "${var.project_name}-db-subnets-${random_id.db_name_suffix.hex}"
  subnet_ids = var.subnet_ids

  tags = {
    Name    = "${var.project_name}-db-subnets"
    Project = var.project_name
    Cloud   = "aws"
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_db_instance" "main" {
  identifier                  = "${var.project_name}-db-${random_id.db_name_suffix.hex}"
  engine                      = "postgres"
  engine_version              = var.engine_version
  instance_class              = var.instance_class
  allocated_storage           = var.allocated_storage
  storage_type                = var.storage_type
  db_name                     = var.db_name
  username                    = var.db_username
  password                    = var.db_password
  port                        = var.db_port
  db_subnet_group_name        = aws_db_subnet_group.database.name
  vpc_security_group_ids      = [aws_security_group.database.id]
  publicly_accessible         = false
  multi_az                    = var.multi_az
  backup_retention_period     = var.backup_retention_period
  deletion_protection         = true
  skip_final_snapshot         = false
  final_snapshot_identifier   = "${var.project_name}-db-final-${random_id.db_name_suffix.hex}"
  auto_minor_version_upgrade  = true
  allow_major_version_upgrade = false

  tags = {
    Name    = "${var.project_name}-db"
    Project = var.project_name
    Cloud   = "aws"
  }

  lifecycle {
    prevent_destroy = true
  }
}
