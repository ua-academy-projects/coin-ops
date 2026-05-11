locals {
  queue                 = var.runtime.queue
  main_topic_name       = "${var.name_prefix}-${local.queue.name}"
  dead_letter_name      = "${var.name_prefix}-${local.queue.name}-dlq"
  subscription_name     = "${var.name_prefix}-${local.queue.name}-sub"
  max_delivery_attempts = max(5, local.queue.max_receive_count)
  pubsub_service_member = "serviceAccount:service-${data.google_project.current.number}@gcp-sa-pubsub.iam.gserviceaccount.com"
  app_member            = "serviceAccount:${var.app_service_account_email}"
}

data "google_project" "current" {
  project_id = var.project_id
}

resource "google_pubsub_topic" "dead_letter" {
  count = local.queue.dead_letter ? 1 : 0

  name = local.dead_letter_name
}

resource "google_pubsub_topic" "main" {
  name = local.main_topic_name
}

resource "google_pubsub_subscription" "main" {
  name                 = local.subscription_name
  topic                = google_pubsub_topic.main.name
  ack_deadline_seconds = local.queue.visibility_timeout_seconds

  dynamic "dead_letter_policy" {
    for_each = local.queue.dead_letter ? [1] : []
    content {
      dead_letter_topic     = google_pubsub_topic.dead_letter[0].id
      max_delivery_attempts = local.max_delivery_attempts
    }
  }

  depends_on = [google_pubsub_topic_iam_member.dead_letter_publisher]
}

resource "google_pubsub_topic_iam_member" "app_publisher" {
  topic  = google_pubsub_topic.main.name
  role   = "roles/pubsub.publisher"
  member = local.app_member
}

resource "google_pubsub_subscription_iam_member" "app_subscriber" {
  subscription = google_pubsub_subscription.main.name
  role         = "roles/pubsub.subscriber"
  member       = local.app_member
}

resource "google_pubsub_topic_iam_member" "dead_letter_publisher" {
  count = local.queue.dead_letter ? 1 : 0

  topic  = google_pubsub_topic.dead_letter[0].name
  role   = "roles/pubsub.publisher"
  member = local.pubsub_service_member
}

resource "google_pubsub_subscription_iam_member" "dead_letter_subscriber" {
  count = local.queue.dead_letter ? 1 : 0

  subscription = local.subscription_name
  role         = "roles/pubsub.subscriber"
  member       = local.pubsub_service_member
}
