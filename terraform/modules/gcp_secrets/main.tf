resource "google_secret_manager_secret" "db_secrets" {
  secret_id = "coinops-db-secrets"

  replication {
    auto {}
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "google_secret_manager_secret_version" "db_secrets_data" {
  secret = google_secret_manager_secret.db_secrets.id

  secret_data = jsonencode({
    DB_PASSWORD       = var.db_password
    RABBITMQ_PASSWORD = var.rabbitmq_password
  })
}

resource "google_secret_manager_secret" "app_secrets" {
  secret_id = "coinops-app-secrets"

  replication {
    auto {}
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "google_secret_manager_secret_version" "app_secrets_data" {
  secret = google_secret_manager_secret.app_secrets.id

  secret_data = jsonencode({
    GHCR_TOKEN           = var.ghcr_token
    CLOUDFLARE_API_TOKEN = var.cloudflare_api_token
  })
}
