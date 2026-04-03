# coin-ops — Terraform AWS Provisioning

Provisions the same 3-node architecture used locally on Hyper-V, on AWS EC2 instead. This is a portfolio/learning deliverable demonstrating portable IaC — the same node roles, the same Ansible playbooks, just running on standard cloud infrastructure.

## Architecture

| Node | EC2 Name | Role | Services |
|------|----------|------|----------|
| node-01 | softserve-node-01 | history | PostgreSQL, RabbitMQ, Python history service |
| node-02 | softserve-node-02 | proxy | Go proxy service |
| node-03 | softserve-node-03 | ui | nginx, static frontend |

All three instances share a VPC (`10.0.0.0/16`) with full internal connectivity. node-03 (ui) is the only node exposed on port 80 to the public internet. SSH is restricted to your IP via the `your_ip` variable.

## Terraform and Ansible — how they fit together

**Terraform provisions, Ansible configures.**

Terraform creates the AWS infrastructure (VPC, subnets, security groups, EC2 instances) and outputs the public IPs. You paste those IPs into `ansible/inventory`, then run the existing Ansible playbooks unchanged. Nothing in the Ansible layer needs to know or care that it's AWS rather than Hyper-V.

```
terraform apply
    └─> outputs public IPs
            └─> paste into ansible/inventory
                    └─> ansible-playbook site.yml
```

## Prerequisites

- AWS account with sufficient EC2/VPC permissions
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html) configured (`aws configure`)
- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.0 installed
- An EC2 key pair created in your target region (AWS Console → EC2 → Key Pairs)

## Usage

### 1. Create `terraform/terraform.tfvars`

```hcl
ami_id        = "ami-0faab6bdbac9486fb"  # Ubuntu 24.04 eu-central-1 — verify in AWS console
key_pair_name = "your-key-pair-name"
your_ip       = "1.2.3.4/32"            # your public IP
```

`terraform.tfvars` is gitignored. Never commit it — it contains your IP and key pair name.

To find the current Ubuntu 24.04 AMI for your region:
```bash
aws ec2 describe-images \
  --owners 099720109477 \
  --filters "Name=name,Values=ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*" \
  --query "sort_by(Images,&CreationDate)[-1].ImageId" \
  --output text \
  --region eu-central-1
```

### 2. Initialise and apply

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

### 3. Copy inventory snippet

After `apply` completes, Terraform prints an `ansible_inventory_snippet` output. Copy the block into `ansible/inventory`, replacing the existing host IPs.

### 4. Run Ansible

```bash
cd ansible
ansible-playbook -i inventory site.yml
```

The playbooks are identical to the Hyper-V setup — no changes needed.

## Teardown

```bash
cd terraform
terraform destroy
```

This removes all AWS resources created by this configuration. There is no persistent storage (EBS root volumes are deleted on termination by default).

## Why not a Hyper-V Terraform provider?

The [Hyper-V Terraform provider](https://registry.terraform.io/providers/taliesins/hyperv) requires Windows and WinRM connectivity to the Hyper-V host, making it impractical to demonstrate in a portable or CI context. AWS achieves the same IaC concept on standard infrastructure that any reviewer can reason about without a local Windows lab.
