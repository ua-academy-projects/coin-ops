output "cache" {
  value = {
    managed   = true
    backend   = "valkey"
    engine    = "valkey"
    host      = aws_elasticache_replication_group.this.primary_endpoint_address
    port      = var.runtime.cache.port
    redis_url = "redis://${aws_elasticache_replication_group.this.primary_endpoint_address}:${var.runtime.cache.port}/0"
    arn       = aws_elasticache_replication_group.this.arn
  }
}
