resource "kubernetes_cluster_role_binding" "jenkins_admin" {
  metadata {
    name = "jenkins-agent-admin"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "cluster-admin"
  }
  subject {
    kind      = "ServiceAccount"
    name      = "jenkins-agent"
    namespace = "jenkins"
  }
}
