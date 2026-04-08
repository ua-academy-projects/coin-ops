variable "winrm_user" {
  description = "Windows administrator username for WinRM connection"
  type        = string
}

variable "winrm_password" {
  description = "Windows administrator password for WinRM connection"
  type        = string
  sensitive   = true
}

variable "winrm_host" {
  description = "Hyper-V host IP (from WSL: run `ip route show default | awk '{print $3}'`)"
  type        = string
  default     = "127.0.0.1"
}

variable "base_vhd_path" {
  description = "Windows path to Ubuntu 24.04 cloud image VHD. Download from https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.vhd"
  type        = string
}

variable "vm_storage_path" {
  description = "Windows path where VM VHDs will be created"
  type        = string
  default     = "F:\\univ\\softserv-internship\\hyper-v\\vms"
}

variable "vm_storage_wsl_path" {
  description = "WSL path to the same VM storage directory (e.g. /mnt/f/univ/softserv-internship/hyper-v/vms)"
  type        = string
  default     = "/mnt/f/univ/softserv-internship/hyper-v/vms"
}

variable "seed_staging_windows_path" {
  description = "Windows path where cloud-init ISOs are staged (same location as seed_staging_wsl_path but Windows notation)"
  type        = string
  default     = "F:\\univ\\softserv-internship\\hyper-v\\seed"
}

variable "seed_staging_wsl_path" {
  description = "WSL path to the same seed staging directory (e.g. /mnt/f/univ/softserv-internship/hyper-v/seed)"
  type        = string
  default     = "/mnt/f/univ/softserv-internship/hyper-v/seed"
}

variable "ssh_public_key" {
  description = "SSH public key content for the vagrant user on all VMs"
  type        = string
}

variable "vm_console_password" {
  description = "Emergency console password for the vagrant user (fallback when SSH key auth is unavailable)"
  type        = string
  sensitive   = true
}

variable "vm_memory_mb" {
  description = "RAM per VM in megabytes"
  type        = number
  default     = 2048
}

variable "vm_processors" {
  description = "CPU cores per VM"
  type        = number
  default     = 2
}

variable "vm_disk_gb" {
  description = "Root disk size per VM in gigabytes (VHDX is resized after clone)"
  type        = number
  default     = 20
}
