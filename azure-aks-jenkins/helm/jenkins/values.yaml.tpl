controller:
  serviceType: LoadBalancer
  numExecutors: 1
  installLatestPlugins: false
  admin:
    existingSecret: ${admin_secret_name}
    userKey: username
    passwordKey: password
  serviceAccount:
    create: true
    name: ${service_account_name}
  installPlugins:
    - kubernetes
    - docker-workflow
    - git
    - workflow-aggregator
    - blueocean
    - credentials-binding
    - configuration-as-code
    - pipeline-stage-view
  persistence:
    enabled: true
    size: ${jenkins_storage_size}
  JCasC:
    defaultConfigScripts:
      platform-config: |
        jenkins:
          systemMessage: "Provisioned by Terraform on AKS."
          clouds:
            - kubernetes:
                name: "kubernetes"
                namespace: "${jenkins_namespace}"
                serverUrl: "https://kubernetes.default"
                jenkinsUrl: "http://jenkins.${jenkins_namespace}.svc.cluster.local:8080"
                jenkinsTunnel: "jenkins-agent.${jenkins_namespace}.svc.cluster.local:50000"
                skipTlsVerify: true
                containerCapStr: "10"
        credentials:
          system:
            domainCredentials:
              - credentials:
                  - usernamePassword:
                      scope: GLOBAL
                      id: "acr-push"
                      username: "${acr_username}"
                      password: "${acr_password}"
                      description: "ACR push credentials"
        unclassified:
          location:
            url: "http://jenkins.${jenkins_namespace}.svc.cluster.local:8080/"
  containerEnv:
    - name: ACR_LOGIN_SERVER
      value: "${acr_login_server}"
    - name: APP_NAMESPACE
      value: "${app_namespace}"
    - name: AZURE_SUBSCRIPTION_ID
      value: "${azure_subscription_id}"
    - name: AZURE_TENANT_ID
      value: "${azure_tenant_id}"
agent:
  enabled: true
