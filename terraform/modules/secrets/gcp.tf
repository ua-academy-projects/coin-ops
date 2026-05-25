resource "google_secret_manager_secret" "app_secrets" {
  count = var.cloud_provider == "gcp" ? 1 : 0

  secret_id = "coinops-app-secrets"

  replication {
    user_managed {
      replicas {
        location = var.region
      }
    }
  }

  labels = var.common_tags
}

resource "google_secret_manager_secret_version" "app_secrets_version" {
  count = var.cloud_provider == "gcp" ? 1 : 0

  secret = google_secret_manager_secret.app_secrets[0].id
  secret_data = jsonencode({
    DATABASE_URL      = "postgresql://${var.db_username}:${var.db_password}@${var.db_host}:5432/${var.db_name}"
    DB_PASSWORD       = var.db_password
    DB_HOST           = var.db_host
    RABBITMQ_PASSWORD = var.rabbitmq_password
  })
}
