output "db_public_ip" {
  value = aws_instance.db_server.public_ip

}
output "web_public_ip" {
  value = aws_instance.web_server.public_ip

}
output "app_public_ip" {
  value = aws_instance.app_server.public_ip

}
