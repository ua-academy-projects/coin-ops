variable "resource_group_name" {
  description = "Resource group for the monitoring lab."
  type        = string
  default     = "navigator"
}

variable "location" {
  description = "Azure region for the monitoring lab."
  type        = string
  default     = "westeurope"
}

variable "prefix" {
  description = "Prefix used in Azure resource names."
  type        = string
  default     = "monitorlab"
}

variable "vm_name" {
  description = "Name of the virtual machine."
  type        = string
  default     = "monitor-vm"
}

variable "admin_username" {
  description = "Admin username for SSH access."
  type        = string
  default     = "azureuser"
}

variable "vm_size" {
  description = "Azure VM size."
  type        = string
  default     = "Standard_D2s_v4"
}

variable "ssh_public_key_path" {
  description = "Path to the SSH public key file used for VM login."
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

variable "allowed_ssh_cidr" {
  description = "CIDR range allowed to connect to the VM over SSH."
  type        = string
  default     = "0.0.0.0/0"
}

variable "alert_email" {
  description = "Email address that should receive Azure Monitor alerts."
  type        = string
  default     = "val.don.ua@gmail.com"
}

variable "cpu_alert_threshold" {
  description = "CPU usage percentage threshold for the VM alert."
  type        = number
  default     = 45
}

variable "cpu_alert_severity" {
  description = "Severity for the CPU metric alert."
  type        = number
  default     = 3
}
