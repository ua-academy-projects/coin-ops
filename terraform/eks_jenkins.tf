
resource "random_password" "jenkins_admin" {
  length  = 24
  special = false
}

resource "helm_release" "jenkins" {
  name             = "jenkins"
  repository       = "https://charts.jenkins.io"
  chart            = "jenkins"
  namespace        = "jenkins"
  create_namespace = true
  wait             = true
  timeout          = 900

  values = [
    templatefile("${path.module}/../helm/jenkins/values.yaml.tftpl", {
      storage_class        = "gp2"
      storage_size         = "8Gi"
      service_account_name = "jenkins"
      public_url           = "https://jenkins.coinops-softserve-penina.pp.ua/"
      casc_config = templatefile("${path.module}/../helm/jenkins/casc.yaml.tftpl", {
        namespace      = "jenkins"
        release_name   = "jenkins"
        public_url     = "https://jenkins.coinops-softserve-penina.pp.ua/"
        job_name       = "coinops-eks-deploy"
        repository_url = "https://github.com/ua-academy-projects/coin-ops.git"
        branch         = "dev-penina-cloud"
        admin_password = jsonencode(random_password.jenkins_admin.result)
        github_username = jsonencode(var.ghcr_username)
        github_token    = jsonencode(var.github_token)
        db_password     = jsonencode(var.db_password)
      })
    })
  ]

  depends_on = [module.aws_eks, module.aws_irsa]
}

resource "kubernetes_cluster_role_binding" "jenkins_cluster_admin" {
  metadata {
    name = "jenkins-cluster-admin"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "cluster-admin"
  }
  subject {
    kind      = "ServiceAccount"
    name      = "jenkins"
    namespace = "jenkins"
  }
  depends_on = [helm_release.jenkins]
}

# Cloudflare DNS record for Jenkins
resource "cloudflare_record" "jenkins" {
  zone_id = var.cloudflare_zone_id
  name    = "jenkins"
  type    = "CNAME"
  content = "jenkins-tunnel.coinops-softserve-penina.pp.ua"
  proxied = true
}

# Cloudflare Zero Trust tunnel for Jenkins
resource "cloudflare_zero_trust_tunnel_cloudflared" "jenkins" {
  account_id = var.cloudflare_account_id
  name       = "coinops-jenkins"
  secret     = base64encode(random_password.jenkins_admin.result)
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "jenkins" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.jenkins.id

  config {
    ingress_rule {
      hostname = "jenkins.coinops-softserve-penina.pp.ua"
      service  = "http://jenkins.jenkins.svc.cluster.local:8080"
    }
    ingress_rule {
      service = "http_status:404"
    }
  }
}

output "jenkins_admin_password" {
  value     = random_password.jenkins_admin.result
  sensitive = true
}

output "jenkins_tunnel_token" {
  value     = cloudflare_zero_trust_tunnel_cloudflared.jenkins.tunnel_token
  sensitive = true
}
