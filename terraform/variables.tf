variable "libvirt_uri" {
  description = "URI підключення до libvirt (локальний або SSH)"
  type        = string
  default     = "qemu:///system"
  # Приклади:
  # локально:   "qemu:///system"
  # через SSH:  "qemu+ssh://user@HOST/system"
}

variable "storage_pool" {
  description = "Libvirt storage pool для дисків і ISO"
  type        = string
  default     = "default"
}

variable "alpine_image_url" {
  description = "Шлях або URL до Alpine cloud-init qcow2 образу"
  type        = string
  # Завантажити: https://alpinelinux.org/cloud/
  # Наприклад: alpine-virt-3.19.1-x86_64.qcow2
  default     = "/var/lib/libvirt/images/alpine-virt-3.19.1-x86_64.qcow2"
}

variable "ssh_public_key" {
  description = "SSH публічний ключ для доступу до VM"
  type        = string
  # Наприклад: "ssh-ed25519 AAAA... user@host"
}

variable "db_password" {
  description = "Пароль для PostgreSQL користувача monero"
  type        = string
  sensitive   = true
}

variable "deploy_git_repo" {
  description = "URL git-репозиторію для автодеплою"
  type        = string
  default     = "https://github.com/ua-academy-projects/coin-ops.git"
}

variable "deploy_branch" {
  description = "Git гілка для деплою"
  type        = string
  default     = "main"
}

variable "monero_rpc_host" {
  description = "IP або hostname monerod RPC"
  type        = string
  default     = "127.0.0.1"
}

variable "monero_rpc_port" {
  description = "Порт monerod RPC"
  type        = number
  default     = 18081
}
