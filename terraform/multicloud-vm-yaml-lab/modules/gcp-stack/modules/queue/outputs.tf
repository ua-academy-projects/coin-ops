output "queue" {
  value = {
    backend      = "pubsub"
    name         = local.queue.name
    topic        = google_pubsub_topic.main.name
    subscription = google_pubsub_subscription.main.name
    url          = ""
    arn          = ""
    dead_letter  = try(google_pubsub_topic.dead_letter[0].name, "")
  }
}
