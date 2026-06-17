# ==============================================================================
# AWS EKS Cluster Configuration
# ==============================================================================

# Fetch the latest EKS optimized AMI for worker nodes
data "aws_ssm_parameter" "eks_ami_release_version" {
  name = "/aws/service/eks/optimized-ami/${var.eks_cluster_version}/amazon-linux-2/recommended/release_version"
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.0"

  cluster_name    = "${var.environment}-eks-cluster"
  cluster_version = var.eks_cluster_version

  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.private_subnets
  control_plane_subnet_ids = module.vpc.intra_subnets

  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = true

  # Enable OIDC provider for IRSA (IAM Roles for Service Accounts)
  enable_irsa = true

  eks_managed_node_groups = {
    default = {
      min_size     = 2
      max_size     = 5
      desired_size = 2

      instance_types = ["t3.medium"]
      capacity_type  = "ON_DEMAND"
      
      # Ensure CloudWatch Agent policy is attached so Container Insights works
      iam_role_additional_policies = {
        CloudWatchAgentServerPolicy = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
      }
    }
  }

  tags = {
    Environment = var.environment
  }
}

# ==============================================================================
# Providers for interacting with the cluster inside Terraform
# ==============================================================================
provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
      command     = "aws"
    }
  }
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
    command     = "aws"
  }
}

# ==============================================================================
# Essential Cluster Resources (Storage & Secrets)
# ==============================================================================

resource "kubernetes_storage_class" "ebs_sc" {
  metadata {
    name = "ebs-sc"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true" # Critical for CNPG Postgres
    }
  }
  storage_provisioner = "ebs.csi.aws.com"
  volume_binding_mode = "WaitForFirstConsumer"
  parameters = {
    type = "gp3"
  }
  depends_on = [module.eks]
}

resource "kubernetes_manifest" "cluster_secret_store" {
  manifest = {
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ClusterSecretStore"
    metadata = {
      name = "cloud-secret-store"
    }
    spec = {
      provider = {
        aws = {
          service = "SecretsManager"
          region  = "us-east-1"
          auth = {
            jwt = {
              serviceAccountRef = {
                name      = "external-secrets"
                namespace = "external-secrets"
              }
            }
          }
        }
      }
    }
  }
  depends_on = [helm_release.external_secrets]
}

# ==============================================================================
# IAM Role for EBS CSI Driver
# ==============================================================================
module "ebs_csi_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name             = "${var.environment}-ebs-csi-role"
  attach_ebs_csi_policy = true

  oidc_providers = {
    ex = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }
}

# ==============================================================================
# EKS Add-ons (Including CloudWatch Container Insights & EBS)
# ==============================================================================
resource "aws_eks_addon" "cloudwatch_observability" {
  cluster_name                = module.eks.cluster_name
  addon_name                  = "amazon-cloudwatch-observability"
  resolve_conflicts_on_update = "PRESERVE"
  
  depends_on = [module.eks.eks_managed_node_groups]
}

# resource "aws_eks_addon" "vpc_cni" {
#   cluster_name = module.eks.cluster_name
#   addon_name   = "vpc-cni"
# }

resource "aws_eks_addon" "vpc_cni" {
  cluster_name = module.eks.cluster_name
  addon_name   = "vpc-cni"
  resolve_conflicts_on_update = "PRESERVE"
}

resource "aws_eks_addon" "ebs_csi" {
  cluster_name             = module.eks.cluster_name
  addon_name               = "aws-ebs-csi-driver"
  service_account_role_arn = module.ebs_csi_irsa_role.iam_role_arn
}

# ==============================================================================
# NGINX Ingress Controller
# ==============================================================================
resource "helm_release" "nginx_ingress" {
  name       = "ingress-nginx"
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  namespace  = "ingress-nginx"
  create_namespace = true
  version    = "4.10.1"

  set {
    name  = "controller.service.type"
    value = "LoadBalancer"
  }
  
  set {
    name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-type"
    value = "nlb"
  }

  depends_on = [module.eks]
}

# ==============================================================================
# Jenkins Installation (Inside EKS)
# ==============================================================================
resource "helm_release" "jenkins" {
  name             = "jenkins"
  repository       = "https://charts.jenkins.io"
  chart            = "jenkins"
  namespace        = "jenkins"
  create_namespace = true
  timeout          = 600
  version          = "5.9.26"

  # We use the AWS EBS Storage Class created by the CSI driver


  set {
    name  = "persistence.storageClass"
    value = "ebs-sc"
  }

  set {
    name  = "persistence.size"
    value = "20Gi"
  }



  set {
    name  = "controller.image.tag"
    value = "2.556-jdk21"
  }

  set {
    name  = "controller.javaOpts"
    value = "-Djava.net.preferIPv4Stack=true"
  }

  set {
    name  = "controller.initContainerEnv[0].name"
    value = "JAVA_OPTS"
  }
  set {
    name  = "controller.initContainerEnv[0].value"
    value = "-Djava.net.preferIPv4Stack=true"
  }
  set {
    name  = "controller.initContainerEnv[1].name"
    value = "PLUGIN_CLI_OPTS"
  }
  set {
    name  = "controller.initContainerEnv[1].value"
    value = "-Djava.net.preferIPv4Stack=true"
  }
  set {
    name  = "controller.initContainerEnv[2].name"
    value = "JENKINS_UC"
  }
  set {
    name  = "controller.initContainerEnv[2].value"
    value = "https://eastamerica.cloudflare.jenkins.io/current"
  }
  set {
    name  = "controller.initContainerEnv[3].name"
    value = "JENKINS_PLUGIN_INFO"
  }
  set {
    name  = "controller.initContainerEnv[3].value"
    value = "https://eastamerica.cloudflare.jenkins.io/plugin-versions.json"
  }

  # Inject the IRSA role into Jenkins agent service account
  set {
    name  = "agent.serviceAccount.create"
    value = "true"
  }

  set {
    name  = "agent.serviceAccount.name"
    value = "jenkins-agent"
  }

  set {
    name  = "agent.serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.jenkins_agent_role.arn
  }

  depends_on = [
    module.eks,
    aws_eks_addon.ebs_csi
  ]
}

# ==============================================================================
# Required Operators for Coin-Ops Helm Chart (CRDs)
# ==============================================================================

# 1. Cert-Manager (For Let's Encrypt TLS)
resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  namespace        = "cert-manager"
  create_namespace = true
  version          = "v1.14.4"

  set {
    name  = "installCRDs"
    value = "true"
  }
  depends_on = [module.eks]
}

# 2. CloudNativePG (For Postgres)
resource "helm_release" "cnpg" {
  name             = "cnpg"
  repository       = "https://cloudnative-pg.github.io/charts"
  chart            = "cloudnative-pg"
  namespace        = "cnpg-system"
  create_namespace = true
  version          = "0.21.2"
  depends_on       = [module.eks]
}

# 3. External Secrets Operator (For integrating with AWS Secrets Manager)
resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  namespace        = "external-secrets"
  create_namespace = true
  version          = "0.9.20"

  set {
    name  = "installCRDs"
    value = "true"
  }

  # Allow the operator to assume the AWS IRSA role
  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.external_secrets_role.arn
  }

  depends_on = [module.eks]
}
