# =============================================================================
# k3s/helm.tf
# =============================================================================
# Deploys the following add-ons via Helm once the k3s cluster API is ready:
#
#   1. Cilium       — CNI (networking, routing, network policies, eBPF)
#   2. cert-manager — Automatic TLS certificate provisioning (Let's Encrypt)
#   3. NGINX Ingress— Ingress controller (routes HTTP/HTTPS to services)
#   4. Headlamp     — Kubernetes dashboard (read-only, token-auth)
#
# Deployment order:
#   Cilium → (cluster networking ready) → cert-manager → NGINX → Headlamp
#
# Prerequisites:
#   • The SSH tunnel must be open before running `terraform apply`:
#       gcloud compute ssh k3s-bastion --tunnel-through-iap \
#         -- -L 16443:<LB_INTERNAL_IP>:6443 -N &
#   • The kubeconfig from node-0 must be merged into ~/.kube/config.
#     Use the fetch_kubeconfig output after first apply.
# =============================================================================

# ─── Cilium CNI ───────────────────────────────────────────────────────────────
# Cilium replaces Flannel (disabled in k3s with --flannel-backend=none).
# It provides:
#   • eBPF-based pod networking and routing
#   • Native NetworkPolicy enforcement
#   • Hubble observability (optional — enable with hubble.enabled=true)
#
# Key parameters:
#   k8sServiceHost/Port  : Points to the k3s API LB (not localhost)
#   ipam.mode=kubernetes : Delegate IP allocation to kube-controller-manager
#   kubeProxyReplacement : Replace kube-proxy with Cilium eBPF (optional)

resource "helm_release" "cilium" {
  name             = "cilium"
  repository       = "https://helm.cilium.io"
  chart            = "cilium"
  version          = local.cilium_version
  namespace        = "kube-system"
  create_namespace = false # kube-system already exists

  # Wait for all Cilium pods to be Running before proceeding
  wait          = true
  wait_for_jobs = true
  timeout       = 600

  set {
    name  = "k8sServiceHost"
    value = google_compute_address.k3s_api_vip.address
  }

  set {
    name  = "k8sServicePort"
    value = "6443"
  }

  set {
    name  = "ipam.mode"
    value = "kubernetes"
  }

  set {
    name  = "kubeProxyReplacement"
    value = "partial" # safe default; change to 'strict' after validation
  }

  set {
    name  = "hostServices.enabled"
    value = "false"
  }

  set {
    name  = "externalIPs.enabled"
    value = "true"
  }

  set {
    name  = "nodePort.enabled"
    value = "true"
  }

  set {
    name  = "hostPort.enabled"
    value = "true"
  }

  set {
    name  = "image.pullPolicy"
    value = "IfNotPresent"
  }

  set {
    name  = "operator.replicas"
    value = "1" # single operator replica is sufficient for 3-node cluster
  }

  # Enable Hubble observability (optional but recommended)
  set {
    name  = "hubble.enabled"
    value = "true"
  }

  set {
    name  = "hubble.relay.enabled"
    value = "true"
  }

  depends_on = [time_sleep.wait_for_k3s]
}

# ─── cert-manager ─────────────────────────────────────────────────────────────
# cert-manager automates TLS certificate provisioning from Let's Encrypt
# (via ACME HTTP-01 or DNS-01 challenges) and internal CAs.
#
# After deployment, create a ClusterIssuer for Let's Encrypt:
#
#   apiVersion: cert-manager.io/v1
#   kind: ClusterIssuer
#   metadata:
#     name: letsencrypt-prod
#   spec:
#     acme:
#       server: https://acme-v02.api.letsencrypt.org/directory
#       email: admin@example.com
#       privateKeySecretRef:
#         name: letsencrypt-prod
#       solvers:
#         - http01:
#             ingress:
#               class: nginx

resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  version          = local.cert_manager_version
  namespace        = "cert-manager"
  create_namespace = true

  wait    = true
  timeout = 300

  set {
    name  = "installCRDs"
    value = "true" # install cert-manager CRDs in the same release
  }

  set {
    name  = "replicaCount"
    value = "1"
  }

  set {
    name  = "webhook.replicaCount"
    value = "1"
  }

  set {
    name  = "cainjector.replicaCount"
    value = "1"
  }

  depends_on = [helm_release.cilium]
}

# ─── NGINX Ingress Controller ─────────────────────────────────────────────────
# NGINX Ingress replaces the disabled Traefik.
# It is deployed in DaemonSet mode so that all 3 nodes serve as ingress
# endpoints — the GCP external TCP LB routes to NodePort 30080/30443.
#
# NodePort values match the firewall rules and LB backend health checks.

resource "helm_release" "nginx_ingress" {
  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  version          = local.nginx_ingress_version
  namespace        = "ingress-nginx"
  create_namespace = true

  wait    = true
  timeout = 300

  # Use DaemonSet so every k3s node serves ingress traffic
  set {
    name  = "controller.kind"
    value = "DaemonSet"
  }

  # NodePort for HTTP (matches LB backend and firewall rule)
  set {
    name  = "controller.service.type"
    value = "NodePort"
  }

  set {
    name  = "controller.service.nodePorts.http"
    value = "30080"
  }

  set {
    name  = "controller.service.nodePorts.https"
    value = "30443"
  }

  # Use host network for maximum throughput (optional — disable if security policy requires)
  set {
    name  = "controller.hostNetwork"
    value = "true"
  }

  # Enable Prometheus metrics (optional)
  set {
    name  = "controller.metrics.enabled"
    value = "true"
  }

  depends_on = [helm_release.cert_manager]
}

# ─── Headlamp Dashboard ───────────────────────────────────────────────────────
# Headlamp is a modern, extensible Kubernetes dashboard.
# It is deployed with ClusterIP service — access via kubectl port-forward:
#
#   kubectl -n headlamp port-forward svc/headlamp 4466:80 &
#   open http://localhost:4466
#
# Authentication: use a ServiceAccount token (see outputs for instructions).

resource "helm_release" "headlamp" {
  name             = "headlamp"
  repository       = "https://kubernetes-sigs.github.io/headlamp/"
  chart            = "headlamp"
  version          = local.headlamp_version
  namespace        = "headlamp"
  create_namespace = true

  wait    = true
  timeout = 180

  set {
    name  = "service.type"
    value = "ClusterIP" # not exposed externally; accessed via port-forward
  }

  set {
    name  = "replicaCount"
    value = "1"
  }

  depends_on = [helm_release.nginx_ingress]
}

# ─── Headlamp ClusterRoleBinding (admin access for the dashboard SA) ──────────
resource "kubernetes_cluster_role_binding" "headlamp_admin" {
  metadata {
    name = "headlamp-admin"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "cluster-admin"
  }

  subject {
    kind      = "ServiceAccount"
    name      = "headlamp"
    namespace = "headlamp"
  }

  depends_on = [helm_release.headlamp]
}

# ─── Prometheus Stack ─────────────────────────────────────────────────────────
# kube-prometheus-stack installs Prometheus, Grafana, Alertmanager, and node-exporter.
resource "helm_release" "prometheus" {
  name             = "prometheus"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  version          = local.prometheus_version
  namespace        = "monitoring"
  create_namespace = true

  wait    = true
  timeout = 600

  # Disable prometheus-node-exporter if you have issues with host network,
  # but it is usually fine.
  
  # Set up persistent storage using local-path (k3s default)
  set {
    name  = "prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.storageClassName"
    value = "local-path"
  }
  set {
    name  = "prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.accessModes[0]"
    value = "ReadWriteOnce"
  }
  set {
    name  = "prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.resources.requests.storage"
    value = "10Gi"
  }

  depends_on = [helm_release.nginx_ingress]
}

# ─── Loki Stack ───────────────────────────────────────────────────────────────
# loki-stack installs Loki and Promtail. Promtail forwards logs to Loki.
# Loki acts as a datasource in Grafana (installed by Prometheus stack).
resource "helm_release" "loki" {
  name             = "loki"
  repository       = "https://grafana.github.io/helm-charts"
  chart            = "loki-stack"
  version          = local.loki_version
  namespace        = "monitoring"
  create_namespace = true

  wait    = true
  timeout = 300

  set {
    name  = "promtail.enabled"
    value = "true"
  }

  set {
    name  = "loki.persistence.enabled"
    value = "true"
  }
  
  set {
    name  = "loki.persistence.storageClassName"
    value = "local-path"
  }

  set {
    name  = "loki.persistence.size"
    value = "10Gi"
  }

  # Grafana is installed by Prometheus, so we don't need loki-stack to install it
  set {
    name  = "grafana.enabled"
    value = "false"
  }
  
  set {
    name  = "loki.isDefault"
    value = "false"
  }

  set {
    name  = "prometheus.enabled"
    value = "false"
  }
  
  set {
    name  = "prometheus.isDefault"
    value = "false"
  }

  depends_on = [helm_release.prometheus]
}

# ─── Tailscale Operator ───────────────────────────────────────────────────────
resource "helm_release" "tailscale" {
  name             = "tailscale-operator"
  repository       = "https://pkgs.tailscale.com/helmcharts"
  chart            = "tailscale-operator"
  version          = local.tailscale_version
  namespace        = "tailscale"
  create_namespace = true

  wait    = true
  timeout = 300

  set {
    name  = "oauth.clientId"
    value = data.google_secret_manager_secret_version.tailscale_oauth_id.secret_data
  }

  set_sensitive {
    name  = "oauth.clientSecret"
    value = data.google_secret_manager_secret_version.tailscale_oauth_secret.secret_data
  }

  depends_on = [helm_release.cilium]
}
