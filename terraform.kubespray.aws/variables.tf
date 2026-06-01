variable "region" {
  description = "AWS region for the Kubespray cluster."
  type        = string
  default     = "eu-central-1"
}

variable "cluster_name" {
  description = "Prefix for all AWS resources."
  type        = string
  default     = "kubespray-aws"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.42.0.0/16"
}

variable "subnet_cidrs" {
  description = "CIDR blocks for public and private subnets."
  type = object({
    public_a  = string
    public_b  = string
    private_a = string
    private_b = string
  })
  default = {
    public_a  = "10.42.0.0/24"
    public_b  = "10.42.1.0/24"
    private_a = "10.42.10.0/24"
    private_b = "10.42.11.0/24"
  }
}

variable "availability_zones" {
  description = "Availability zones used by public and private subnets."
  type = object({
    public_a  = string
    public_b  = string
    private_a = string
    private_b = string
  })
  default = {
    public_a  = "eu-central-1a"
    public_b  = "eu-central-1b"
    private_a = "eu-central-1a"
    private_b = "eu-central-1b"
  }
}

variable "allowed_source_cidr" {
  description = "Public CIDR allowed to SSH to bastion and access the Kubernetes API."
  type        = string
}

variable "ssh_public_key_path" {
  description = "Path to the public SSH key to register as an AWS key pair."
  type        = string
}

variable "ami_id" {
  description = "AMI ID used for bastion and cluster nodes."
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type for all Kubernetes nodes."
  type        = string
  default     = "t3.medium"
}

variable "bastion_instance_type" {
  description = "EC2 instance type for the bastion host."
  type        = string
  default     = "t3.micro"
}

variable "ssh_user" {
  description = "SSH user expected on the chosen AMI."
  type        = string
  default     = "ubuntu"
}

variable "node_private_ips" {
  description = "Private IPs assigned to the three control-plane nodes."
  type = object({
    cp_1     = string
    worker_1 = string
    worker_2 = string
  })
  default = {
    cp_1     = "10.42.10.10"
    worker_1 = "10.42.10.11"
    worker_2 = "10.42.11.12"
  }
}

variable "ingress_http_nodeport" {
  description = "HTTP NodePort used by ingress-nginx."
  type        = number
  default     = 30080
}

variable "ingress_https_nodeport" {
  description = "HTTPS NodePort reserved for ingress-nginx."
  type        = number
  default     = 30443
}

variable "headlamp_nodeport" {
  description = "Private NodePort used by Headlamp."
  type        = number
  default     = 30082
}

variable "tls_certificate_arn" {
  description = "Optional ACM certificate ARN for the ALB HTTPS listener."
  type        = string
  default     = null
}

variable "tags" {
  description = "Extra tags applied to created resources."
  type        = map(string)
  default     = {}
}
