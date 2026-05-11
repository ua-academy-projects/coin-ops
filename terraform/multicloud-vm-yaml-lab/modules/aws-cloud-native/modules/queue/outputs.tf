output "queue" {
  value = {
    backend      = "sqs"
    name         = local.queue.name
    url          = aws_sqs_queue.main.url
    arn          = aws_sqs_queue.main.arn
    dead_letter  = try(aws_sqs_queue.dead_letter[0].url, "")
    subscription = ""
    topic        = ""
  }
}

output "app_instance_profile_name" {
  value = var.app_instance_profile_name
}
