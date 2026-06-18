resource "kubernetes_namespace" "this" {
  metadata {
    name = var.jenkins.namespace
  }
}

resource "kubernetes_secret" "admin" {
  metadata {
    name      = var.jenkins.admin_secret_name
    namespace = kubernetes_namespace.this.metadata[0].name
  }

  data = {
    chart-admin-username = var.jenkins.admin_username
    chart-admin-password = var.jenkins.admin_password_placeholder
  }

  type = "Opaque"
}

resource "helm_release" "jenkins" {
  name       = var.jenkins.release_name
  repository = var.jenkins.chart_repository
  chart      = var.jenkins.chart_name
  namespace  = kubernetes_namespace.this.metadata[0].name

  values = [
    yamlencode({
      controller = {
        serviceType = var.jenkins.service_type
        admin = {
          createSecret   = false
          existingSecret = kubernetes_secret.admin.metadata[0].name
          userKey        = "chart-admin-username"
          passwordKey    = "chart-admin-password"
        }
        JCasC = {
          defaultConfig         = false
          securityRealm         = ""
          authorizationStrategy = ""
          configScripts = {
            "coin-ops" = yamlencode({
              jenkins = {
                systemMessage = var.jenkins.jcasc.system_message
                securityRealm = {
                  local = {
                    allowsSignup = false
                    users = [
                      {
                        id       = var.jenkins.admin_username
                        password = var.jenkins.admin_password_placeholder
                      }
                    ]
                  }
                }
                authorizationStrategy = {
                  loggedInUsersCanDoAnything = {
                    allowAnonymousRead = false
                  }
                }
                clouds = [
                  {
                    kubernetes = {
                      name                  = "aks"
                      namespace             = var.jenkins.jcasc.agent_namespace
                      serverUrl             = "https://kubernetes.default"
                      jenkinsUrl            = var.jenkins.jcasc.jenkins_url
                      jenkinsTunnel         = "${var.jenkins.release_name}-agent.${var.jenkins.namespace}.svc.cluster.local:50000"
                      maxRequestsPerHostStr = "32"
                      templates = [
                        {
                          name           = "aks-agent"
                          label          = var.jenkins.jcasc.agent_label
                          serviceAccount = var.jenkins.jcasc.agent_service_account
                          namespace      = var.jenkins.jcasc.agent_namespace
                          idleMinutes    = 10
                          instanceCap    = 5
                          containers = [
                            {
                              name       = "jnlp"
                              image      = "jenkins/inbound-agent:latest"
                              workingDir = "/home/jenkins/agent"
                            }
                          ]
                        }
                      ]
                    }
                  }
                ]
              }
              unclassified = {
                location = {
                  url = var.jenkins.jcasc.jenkins_url
                }
              }
            })
          }
        }
      }
    })
  ]

  depends_on = [kubernetes_secret.admin]
}
