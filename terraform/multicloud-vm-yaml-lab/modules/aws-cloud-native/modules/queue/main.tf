locals {
  queue = var.runtime.queue
}

resource "aws_sqs_queue" "dead_letter" {
  count = local.queue.dead_letter ? 1 : 0

  name = "${var.name_prefix}-${local.queue.name}-dlq"
}

resource "aws_sqs_queue" "main" {
  name                       = "${var.name_prefix}-${local.queue.name}"
  visibility_timeout_seconds = local.queue.visibility_timeout_seconds
  redrive_policy = local.queue.dead_letter ? jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dead_letter[0].arn
    maxReceiveCount     = local.queue.max_receive_count
  }) : null
}
