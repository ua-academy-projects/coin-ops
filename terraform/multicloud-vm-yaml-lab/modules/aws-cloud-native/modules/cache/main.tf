locals {
  cache = var.runtime.cache
}

resource "aws_security_group" "cache" {
  name        = "${var.name_prefix}-valkey-sg"
  description = "Managed Valkey access from app instances"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Valkey from app instances"
    from_port       = local.cache.port
    to_port         = local.cache.port
    protocol        = "tcp"
    security_groups = [var.app_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name_prefix}-valkey-sg" }
}

resource "aws_elasticache_subnet_group" "this" {
  name       = "${var.name_prefix}-valkey-subnets"
  subnet_ids = values(var.private_subnet_ids)

  tags = { Name = "${var.name_prefix}-valkey-subnets" }
}

resource "aws_elasticache_replication_group" "this" {
  replication_group_id = "${var.name_prefix}-valkey"
  description          = "${var.name_prefix} managed Valkey sessions"

  engine         = "valkey"
  engine_version = tostring(local.cache.aws_engine_version)
  node_type      = local.cache.aws_node_type
  port           = local.cache.port

  num_cache_clusters         = 1 + local.cache.aws_replicas
  automatic_failover_enabled = local.cache.aws_replicas > 0
  multi_az_enabled           = local.cache.aws_replicas > 0

  subnet_group_name  = aws_elasticache_subnet_group.this.name
  security_group_ids = [aws_security_group.cache.id]

  at_rest_encryption_enabled = true
  transit_encryption_enabled = false
  apply_immediately          = true

  tags = { Name = "${var.name_prefix}-valkey" }
}
