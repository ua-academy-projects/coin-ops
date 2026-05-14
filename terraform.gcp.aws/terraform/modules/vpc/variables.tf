variable "cloud" {
  description = "Selected cloud provider: gcp or aws."
  type        = string
}

variable "config" {
  description = "Decoded infrastructure config."
  type        = any
}
