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

resource "kubernetes_service_account" "deployer" {
  metadata {
    name      = var.jenkins.jcasc.agent_service_account
    namespace = kubernetes_namespace.this.metadata[0].name
    annotations = {
      "azure.workload.identity/client-id" = var.workload_identity_client_id
      "azure.workload.identity/tenant-id" = var.workload_identity_tenant_id
    }
  }
}

resource "kubernetes_cluster_role_binding" "deployer" {
  metadata {
    name = "${var.jenkins.release_name}-deployer"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "cluster-admin"
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.deployer.metadata[0].name
    namespace = kubernetes_namespace.this.metadata[0].name
  }
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
        additionalPlugins = [
          "job-dsl:latest",
          "pipeline-utility-steps:latest"
        ]
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
                globalNodeProperties = [
                  {
                    envVars = {
                      env = [
                        {
                          key   = "AZ_KEYVAULT_NAME"
                          value = var.azure_key_vault_name
                        },
                        {
                          key   = "AZURE_CLIENT_ID"
                          value = var.workload_identity_client_id
                        },
                        {
                          key   = "AZURE_TENANT_ID"
                          value = var.workload_identity_tenant_id
                        },
                        {
                          key   = "AZURE_FEDERATED_TOKEN_FILE"
                          value = var.workload_identity_token_file
                        },
                        {
                          key   = "AZURE_AUTHORITY_HOST"
                          value = var.workload_identity_authority_host
                        }
                      ]
                    }
                  }
                ]
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
                          yaml           = "metadata:\n  labels:\n    azure.workload.identity/use: \"true\"\n"
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
              jobs = [
                {
                  script = <<-EOT
                    pipelineJob('${var.jenkins.deploy_job.name}') {
                      description('Deploys Coin-Ops to AKS with Helm using Azure Workload Identity.')
                      parameters {
                        stringParam('IMAGE_TAG', '', 'Optional image tag override. Empty uses configs/aks.json deploy.image_tag.')
                      }
                      definition {
                        cpsScm {
                          scm {
                            git {
                              remote {
                                url('${var.jenkins.deploy_job.repo_url}')
                              }
                              branches('${var.jenkins.deploy_job.branch}')
                            }
                          }
                          scriptPath('${var.jenkins.deploy_job.script_path}')
                        }
                      }
                    }
                  EOT
                }
              ]
            })
          }
        }
      }
    })
  ]

  depends_on = [
    kubernetes_cluster_role_binding.deployer,
    kubernetes_secret.admin
  ]
}
