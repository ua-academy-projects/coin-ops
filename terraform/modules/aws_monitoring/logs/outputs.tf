output "bucket_name" {
  value = aws_s3_bucket.alb_logs.bucket
}

output "bucket_arn" {
  value = aws_s3_bucket.alb_logs.arn
}
