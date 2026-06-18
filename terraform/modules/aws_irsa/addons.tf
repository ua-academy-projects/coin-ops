# EBS CSI Driver — lets PVCs actually provision real AWS EBS volumes.
# Secrets Store CSI Driver — lets a pod mount an SSM parameter as a file.
# Both are EKS addons, each with its own IRSA role.

resource "aws_iam_role" "ebs_csi" {
  name = "${var.cluster_name}-ebs-csi-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.eks.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${replace(var.oidc_issuer_url, "https://", "")}:sub" = "system:serviceaccount:kube-system:ebs-csi-controller-sa"
          "${replace(var.oidc_issuer_url, "https://", "")}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = { Name = "${var.cluster_name}-ebs-csi-role" }
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

resource "aws_eks_addon" "ebs_csi" {
  cluster_name             = var.cluster_name
  addon_name               = "aws-ebs-csi-driver"
  service_account_role_arn = aws_iam_role.ebs_csi.arn
}

resource "aws_iam_role" "secrets_store_csi" {
  name = "${var.cluster_name}-secrets-csi-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.eks.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${replace(var.oidc_issuer_url, "https://", "")}:sub" = "system:serviceaccount:kube-system:secrets-store-csi-driver-provider-aws"
          "${replace(var.oidc_issuer_url, "https://", "")}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = { Name = "${var.cluster_name}-secrets-csi-role" }
}

# Same /coinops/jenkins/* read scope as the Jenkins IRSA role — this
# driver fetches the secret on Jenkins' behalf.
resource "aws_iam_role_policy" "secrets_store_csi_ssm" {
  name = "${var.cluster_name}-secrets-csi-ssm"
  role = aws_iam_role.secrets_store_csi.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ssm:GetParameter", "ssm:GetParameters"]
      Resource = "arn:aws:ssm:*:*:parameter/coinops/jenkins/*"
    }]
  })
}

