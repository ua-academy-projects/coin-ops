#!/bin/bash
set -euo pipefail

echo "AWS bootstrap resources already exist for this learning project."
echo "Required backend: s3://tfstate-kazachuk-aws-learning/environments/learning/terraform.tfstate"
echo "Required lock table: terraform-state-lock"
echo "Run 'aws configure' before using ./deploy.sh aws init."
