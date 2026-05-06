#!/bin/bash

# Bootstrap script to set up AWS environment for Terraform
# Before running this script, ensure you have configured your AWS CLI (aws configure)
# with an administrator IAM account.

# Configuration variables
IAM_USER_NAME="bootstrap-terraform-user"
REGION="eu-north-1"
BUCKET_NAME="internship-state-bucket-$(date +%s)"

echo "Starting AWS bootstrap process in region: $REGION"

# Create IAM User
echo "Creating IAM User: $IAM_USER_NAME"
aws iam create-user --user-name "$IAM_USER_NAME" > /dev/null

# Assign IAM Policies: Network, VMs, S3
echo "Assigning IAM policies..."
aws iam attach-user-policy \
    --user-name "$IAM_USER_NAME" \
    --policy-arn "arn:aws:iam::aws:policy/AmazonEC2FullAccess"
aws iam attach-user-policy \
    --user-name "$IAM_USER_NAME" \
    --policy-arn "arn:aws:iam::aws:policy/AmazonVPCFullAccess"
aws iam attach-user-policy \
    --user-name "$IAM_USER_NAME" \
    --policy-arn "arn:aws:iam::aws:policy/AmazonS3FullAccess"

# Create S3 Bucket for Terraform remote state
echo "Creating S3 bucket: $BUCKET_NAME"
aws s3api create-bucket \
    --bucket "$BUCKET_NAME" \
    --region "$REGION" \
    --create-bucket-configuration LocationConstraint="$REGION" > /dev/null

# Enable object versioning for state protection
echo "Enabling S3 bucket versioning..."
aws s3api put-bucket-versioning \
    --bucket "$BUCKET_NAME" \
    --versioning-configuration Status=Enabled

# Generate Access Keys
echo "Generating AWS Access Keys..."
CREDENTIALS=$(aws iam create-access-key --user-name "$IAM_USER_NAME" --output text --query 'AccessKey.[AccessKeyId,SecretAccessKey]')

AWS_ACCESS_KEY_ID=$(echo "$CREDENTIALS" | awk '{print $1}')
AWS_SECRET_ACCESS_KEY=$(echo "$CREDENTIALS" | awk '{print $2}')

# Configure local environment and .env
echo "Configuring local environment..."
{
    echo "export AWS_ACCESS_KEY_ID=\"$AWS_ACCESS_KEY_ID\""
    echo "export AWS_SECRET_ACCESS_KEY=\"$AWS_SECRET_ACCESS_KEY\""
    echo "export AWS_DEFAULT_REGION=\"$REGION\""
    echo "export TF_VAR_region=\"$REGION\""
} > aws.env

echo "Bootstrap completed successfully!"