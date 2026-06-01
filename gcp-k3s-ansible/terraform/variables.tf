variable "project_id" {
  description = "GCP project id."
  type        = string
}

variable "region" {
  description = "GCP region."
  type        = string
  default     = "europe-central2"
}

variable "zone" {
  description = "Primary GCP zone."
  type        = string
  default     = "europe-central2-a"
}

variable "cluster_name" {
  description = "Prefix for all resources."
  type        = string
  default     = "k3s-gcp"
}

variable "network_name" {
  description = "VPC network name."
  type        = string
  default     = "k3s-gcp-vpc"
}

variable "subnet_name" {
  description = "Subnetwork name."
  type        = string
  default     = "k3s-gcp-subnet"
}

variable "subnet_cidr" {
  description = "Subnetwork CIDR."
  type        = string
  default     = "10.52.0.0/24"
}

variable "allowed_source_cidr" {
  description = "Admin source CIDR allowed to SSH to bastion and reach the K3s API."
  type        = string
  default     = null
}

variable "ssh_user" {
  description = "SSH user created by the base image."
  type        = string
  default     = "debian"
}

variable "ssh_public_key_path" {
  description = "Path to the public SSH key injected into instances."
  type        = string
}

variable "bastion_machine_type" {
  description = "Machine type for bastion."
  type        = string
  default     = "e2-micro"
}

variable "node_machine_type" {
  description = "Machine type for K3s control-plane nodes."
  type        = string
  default     = "e2-medium"
}

variable "image" {
  description = "Source image used for bastion and cluster nodes."
  type        = string
  default     = "projects/debian-cloud/global/images/family/debian-12"
}

variable "node_private_ips" {
  description = "Private IPs for the three K3s control-plane nodes."
  type = object({
    cp_1 = string
    cp_2 = string
    cp_3 = string
  })
  default = {
    cp_1 = "10.52.0.10"
    cp_2 = "10.52.0.11"
    cp_3 = "10.52.0.12"
  }
}

variable "bastion_private_ip" {
  description = "Private IP of the bastion host."
  type        = string
  default     = "10.52.0.5"
}

variable "tags" {
  description = "Additional labels for instances."
  type        = map(string)
  default     = {}
}

variable "public_web_source_ranges" {
  description = "CIDR ranges allowed to access public HTTP/HTTPS entrypoint."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "traefik_http_nodeport" {
  description = "Traefik HTTP NodePort exposed on K3s nodes."
  type        = number
  default     = 31222
}

variable "traefik_https_nodeport" {
  description = "Traefik HTTPS NodePort exposed on K3s nodes."
  type        = number
  default     = 30191
}

variable "ansible_inventory_path" {
  description = "Path where Terraform should write the generated Ansible inventory file."
  type        = string
  default     = "../ansible/inventory.gcp.generated"
}
