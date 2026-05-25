# =============================================================================
# modules/load_balancer/outputs.tf
# =============================================================================

output "lb_ip" {
  description = "External IP address (GCP) or DNS name (AWS) of the load balancer"
  value = (
    var.cloud_provider == "gcp"
    ? (length(google_compute_global_forwarding_rule.http) > 0 ? google_compute_global_forwarding_rule.http["http"].ip_address : "")
    : (length(aws_lb.this) > 0 ? aws_lb.this[0].dns_name : "")
  )
}

output "lb_id" {
  description = "ID of the GCP forwarding rule or ARN of the AWS ALB"
  value = (
    var.cloud_provider == "gcp"
    ? (length(google_compute_global_forwarding_rule.http) > 0 ? google_compute_global_forwarding_rule.http["http"].id : "")
    : (length(aws_lb.this) > 0 ? aws_lb.this[0].arn : "")
  )
}

output "backend_service_id" {
  description = "ID of the GCP backend service (empty on AWS)"
  value = (
    var.cloud_provider == "gcp"
    ? (length(google_compute_backend_service.this) > 0 ? google_compute_backend_service.this[0].id : "")
    : ""
  )
}

output "target_group_arn" {
  description = "ARN of the AWS target group (empty on GCP)"
  value = (
    var.cloud_provider == "aws"
    ? (length(aws_lb_target_group.this) > 0 ? aws_lb_target_group.this[0].arn : "")
    : ""
  )
}

output "aws_acm_validation_records" {
  description = "DNS records required to validate the AWS ACM certificate"
  value = (
    var.cloud_provider == "aws" && length(var.domains) > 0
    ? aws_acm_certificate.this[0].domain_validation_options
    : null
  )
}
