# =============================================================================
# modules/DB/main.tf
# =============================================================================
# Cloud-agnostic database logic. Resources are separated into:
# - gcp.tf (Google Cloud SQL)
# - aws.tf (Amazon RDS)
# =============================================================================

resource "random_password" "db_password" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}