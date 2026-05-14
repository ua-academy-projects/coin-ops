variable "cloud" {
  type        = string
  description = "Target cloud provider."
}

variable "cloudflare_zone_name" {
  type        = string
  description = "Cloudflare zone name."
}

variable "cloudflare_account_id" {
  type        = string
  description = "Optional Cloudflare account ID."
  default     = ""
}

variable "record_name" {
  type        = string
  description = "DNS record name inside the zone."
}

variable "proxied" {
  type        = bool
  description = "Whether the record should be proxied by Cloudflare."
  default     = true
}

variable "aws_lb_dns_name" {
  type        = string
  description = "AWS load balancer DNS name."
  default     = null
}

variable "gcp_lb_ip_address" {
  type        = string
  description = "GCP load balancer IP address."
  default     = null
}
