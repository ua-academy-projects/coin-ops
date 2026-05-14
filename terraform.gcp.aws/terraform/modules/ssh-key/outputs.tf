output "key_name" {
  value = try(aws_key_pair.main[0].key_name, null)
}
