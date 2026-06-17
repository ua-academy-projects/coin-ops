# GKE add-ons installed by Terraform AFTER the cluster exists: Jenkins (CD) and
# cloudflared (the Cloudflare Zero Trust connector). Gated; see lab.yaml
# clouds.gcp.jenkins.enabled / clouds.gcp.cloudflared.enabled.
#
# !! AUTHORED WITHOUT terraform/gcloud in this env — VALIDATE + iterate on the live
#    cluster. Known footgun: the helm/kubernetes providers (providers.tf) depend on
#    the GKE cluster, so on a FIRST apply run `terraform apply -target=module.gcp`
#    to create the cluster, THEN a normal `terraform apply` installs these add-ons.

locals {
  gke_jenkins_enabled     = local.is_gcp && try(local.stack.gcp.gke.enabled, false) && try(local.stack.gcp.jenkins.enabled, false)
  gke_cloudflared_enabled = local.is_gcp && try(local.stack.gcp.gke.enabled, false) && try(local.stack.gcp.cloudflared.enabled, false)
}

# --- Jenkins (CD) via Helm ----------------------------------------------------
resource "helm_release" "jenkins" {
  count            = local.gke_jenkins_enabled ? 1 : 0
  name             = "jenkins"
  repository       = "https://charts.jenkins.io"
  chart            = "jenkins"
  namespace        = "jenkins"
  create_namespace = true
  values           = [file("${path.module}/../../jenkins/values.yaml")]
  timeout          = 600
}

# Jenkins deploys coinops-app into THIS cluster via its in-cluster ServiceAccount.
# Lab-scope cluster-admin; scope to the coinops namespaces for production.
resource "kubernetes_cluster_role_binding" "jenkins_deploy" {
  count = local.gke_jenkins_enabled ? 1 : 0
  metadata {
    name = "jenkins-deployer"
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

# --- cloudflared connector (Cloudflare Zero Trust) ----------------------------
resource "kubernetes_namespace" "cloudflared" {
  count = local.gke_cloudflared_enabled ? 1 : 0
  metadata {
    name = "cloudflared"
  }
}

resource "kubernetes_secret" "cloudflared_token" {
  count = local.gke_cloudflared_enabled ? 1 : 0
  metadata {
    name      = "cloudflared-token"
    namespace = kubernetes_namespace.cloudflared[0].metadata[0].name
  }
  data = {
    token = data.cloudflare_zero_trust_tunnel_cloudflared_token.gke[0].token
  }
  type = "Opaque"
}

resource "kubernetes_deployment" "cloudflared" {
  count = local.gke_cloudflared_enabled ? 1 : 0
  metadata {
    name      = "cloudflared"
    namespace = kubernetes_namespace.cloudflared[0].metadata[0].name
  }
  spec {
    replicas = 2
    selector {
      match_labels = {
        app = "cloudflared"
      }
    }
    template {
      metadata {
        labels = {
          app = "cloudflared"
        }
      }
      spec {
        container {
          name  = "cloudflared"
          image = "cloudflare/cloudflared:2024.10.0"
          args  = ["tunnel", "--no-autoupdate", "run", "--token", "$(TUNNEL_TOKEN)"]
          env {
            name = "TUNNEL_TOKEN"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.cloudflared_token[0].metadata[0].name
                key  = "token"
              }
            }
          }
        }
      }
    }
  }
}
