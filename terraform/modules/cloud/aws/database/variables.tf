variable "project_name" {
  type        = string
  description = "Project name for resource naming."
}

variable "subnet_ids" {
  type        = list(string)
  description = "Private subnet IDs for the RDS subnet group."
}

variable "vpc_id" {
  type        = string
  description = "VPC ID where the database security group is created."
}

variable "backend_security_group_id" {
  type        = string
  description = "Security group ID for backend application hosts that may connect to RDS."
}

variable "db_password" {
  type        = string
  description = "Password for the database user."
  sensitive   = true
}

variable "db_name" {
  type        = string
  description = "Database name."
  default     = "cognitor"
}

variable "db_username" {
  type        = string
  description = "Database username."
  default     = "cognitor"
}

variable "db_port" {
  type        = number
  description = "Database TCP port."
  default     = 5432
}

variable "engine_version" {
  type        = string
  description = "PostgreSQL major engine version."
  default     = "16"
}

variable "instance_class" {
  type        = string
  description = "RDS instance class."
  default     = "db.t4g.micro"
}

variable "allocated_storage" {
  type        = number
  description = "Allocated RDS storage in GB."
  default     = 20
}

variable "storage_type" {
  type        = string
  description = "RDS storage type."
  default     = "gp3"
}

variable "backup_retention_period" {
  type        = number
  description = "RDS automated backup retention period in days."
  default     = 0
}

variable "multi_az" {
  type        = bool
  description = "Whether to create a Multi-AZ RDS instance."
  default     = false
}
