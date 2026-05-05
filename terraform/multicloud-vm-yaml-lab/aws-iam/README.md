# AWS IAM For Multicloud VM YAML Lab

This policy is intentionally narrower than `AdministratorAccess`.

It allows:

- Terraform state access only under `s3://coinops-leev1tan-terraform-state-001/aws/multicloud-vm-yaml-lab/`
- S3 lock-file access for `use_lockfile = true`
- EC2/VPC operations needed by this lab in `eu-central-1`

It does not store access keys. Store keys in the AWS CLI profile:

```bash
aws configure --profile coinops-lab
aws sts get-caller-identity --profile coinops-lab
```

To create and attach the policy, run with an admin-capable profile:

```bash
cd ~/projects/softserv-internship/terraform/multicloud-vm-yaml-lab
IAM_USER="your-terraform-user" ADMIN_PROFILE="admin" ./aws-iam/create-and-attach-policy.sh
```

Then use the restricted profile for Terraform:

```bash
export AWS_PROFILE=coinops-lab
terraform init -backend-config=backend.aws.hcl -reconfigure
terraform plan
```
