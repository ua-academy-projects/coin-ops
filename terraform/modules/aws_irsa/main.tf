# main.tf — registers the EKS cluster's OIDC issuer as a trusted identity
# provider in AWS IAM. This is the foundational piece for IRSA (IAM Roles
# for Service Accounts) — without this, no pod inside the cluster can ever
# assume an IAM role, no matter how the role itself is configured.
#
# EKS already issues OIDC tokens to every pod automatically — that part
# needs no setup. What's missing is AWS IAM *trusting* those tokens. This
# resource is that one-time trust registration. It does not grant any
# permissions by itself — it only says "tokens signed by this cluster's
# OIDC issuer are valid for IAM to evaluate." The actual permissions come
# from IAM roles created separately (one per pod/use-case — see the
# aws_iam_role resources in this same module for Jenkins, EBS CSI, etc.)
#
# thumbprint: AWS requires a TLS certificate thumbprint for OIDC providers.
# The data source below fetches it directly from the cluster's OIDC
# endpoint rather than hardcoding it, since the certificate could rotate.

data "tls_certificate" "eks_oidc" {
  url = var.oidc_issuer_url
}

resource "aws_iam_openid_connect_provider" "eks" {
  url = var.oidc_issuer_url

  client_id_list = ["sts.amazonaws.com"]

  thumbprint_list = [data.tls_certificate.eks_oidc.certificates[0].sha1_fingerprint]

  tags = { Name = "${var.cluster_name}-oidc-provider" }
}
