output "private_ip" {
  value = aws_instance.this.private_ip
}

# if public ip != "" return public ip else null
output "public_ip" {
  value = aws_instance.this.public_ip != "" ? aws_instance.this.public_ip : null
}

output "instance_id" {
  value = aws_instance.this.id
}