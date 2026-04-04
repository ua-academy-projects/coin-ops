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
  default     = "C:\\HyperV\\vms"
}

variable "seed_staging_windows_path" {
  description = "Windows path (accessible via /mnt) where cloud-init ISOs will be staged before attaching to VMs. E.g. C:\\HyperV\\seed maps to /mnt/c/HyperV/seed in WSL"
  type        = string
  default     = "C:\\HyperV\\seed"
}

variable "seed_staging_wsl_path" {
  description = "The same path as seed_staging_windows_path but in WSL notation. E.g. /mnt/c/HyperV/seed"
  type        = string
  default     = "/mnt/c/HyperV/seed"
}

variable "ssh_public_key" {
  description = "SSH public key content for the vagrant user on all VMs"
  type        = string
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
