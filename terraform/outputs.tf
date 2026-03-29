output "frontend_ip" {
  description = "IP адреса VM1 (Frontend)"
  value       = "10.10.10.11"
}

output "backend_ip" {
  description = "IP адреса VM2 (Backend + Worker)"
  value       = "10.10.10.12"
}

output "db_ip" {
  description = "IP адреса VM3 (PostgreSQL)"
  value       = "10.10.10.13"
}

output "frontend_url" {
  description = "URL дашборду"
  value       = "http://10.10.10.11"
}

output "api_url" {
  description = "URL FastAPI"
  value       = "http://10.10.10.12:8000"
}

output "api_docs_url" {
  description = "URL Swagger документації"
  value       = "http://10.10.10.12:8000/docs"
}

output "ssh_frontend" {
  description = "SSH команда для VM1"
  value       = "ssh deploy@10.10.10.11"
}

output "ssh_backend" {
  description = "SSH команда для VM2"
  value       = "ssh deploy@10.10.10.12"
}

output "ssh_db" {
  description = "SSH команда для VM3"
  value       = "ssh deploy@10.10.10.13"
}
