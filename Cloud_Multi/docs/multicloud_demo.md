# Multi-Cloud Terraform Demo (GCP + AWS)

## GCP Verification

### Terraform

terraform validate\
terraform plan\
terraform apply\
terraform output

### SSH Access

eval \$(ssh-agent -s)\
ssh-add \~/.ssh/id_ed25519

ssh -A -p 9922 marta_ops@`<GCP_JUMP_HOST_EXTERNAL_IP>`{=html}

### Verify SSH Port

sudo ss -tlnp \| grep ssh

Expected: port 9922 is listening

### Verify Agent Forwarding

ssh-add -L

Expected: public key is visible

### Access Internal VM

ssh -p 9922 marta_ops@`<INTERNAL_VM_IP>`{=html}

Result: successful login to internal VM

------------------------------------------------------------------------

## Switch to AWS

Edit config.yaml:

cloud: "aws"

### Terraform

terraform validate\
terraform plan\
terraform apply\
terraform output

------------------------------------------------------------------------

## AWS Verification

### SSH Access

eval \$(ssh-agent -s)\
ssh-add \~/.ssh/id_ed25519

ssh -A -p 9922 marta_ops@`<AWS_JUMP_HOST_EXTERNAL_IP>`{=html}

### Verify SSH Port

sudo ss -tlnp \| grep ssh

Expected: port 9922

### Verify Agent Forwarding

ssh-add -L

### Access Internal VM

ssh -p 9922 marta_ops@`<AWS_INTERNAL_VM_IP>`{=html}

------------------------------------------------------------------------

## Summary

-   Single Terraform root module\
-   Single YAML configuration\
-   Cloud switching via config.yaml\
-   Size abstraction via dictionary\
-   Provider logic encapsulated in modules\
-   Secure SSH access using agent forwarding
