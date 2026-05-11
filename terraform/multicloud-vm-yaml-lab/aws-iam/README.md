# AWS IAM Bootstrap For Multicloud Lab

Run this once with an admin-capable AWS profile. Normal Terraform runs should use the restricted `coinops-lab` profile afterward.

```bash
cd terraform/multicloud-vm-yaml-lab
IAM_USER="terraform-coinops-lab" ADMIN_PROFILE="admin" ./aws-iam/bootstrap.sh
```

The legacy command still works and delegates to the bootstrap script:

```bash
IAM_USER="terraform-coinops-lab" ADMIN_PROFILE="admin" ./aws-iam/create-and-attach-policy.sh
```

The bootstrap creates:

- AWS service-linked roles for Elastic Load Balancing, ElastiCache, and RDS.
- `coinops-lab-app-runtime-role`.
- `coinops-lab-app-runtime-profile`.
- several small customer-managed policies attached to `terraform-coinops-lab`.

The normal Terraform IAM user gets scoped permissions for EC2/VPC, ALB/ACM, Secrets Manager, future RDS/SQS/ElastiCache resources, Terraform state, and `iam:PassRole` only for the app runtime role.

It does **not** require `AdministratorAccess` for normal `terraform plan/apply`.
