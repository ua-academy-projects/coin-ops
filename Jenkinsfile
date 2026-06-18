pipeline {
  agent {
    kubernetes {
      defaultContainer 'node'
      yaml '''
apiVersion: v1
kind: Pod
spec:
  serviceAccountName: jenkins
  containers:
    - name: node
      image: node:22-bookworm-slim
      command:
        - cat
      tty: true
    - name: kaniko
      image: gcr.io/kaniko-project/executor:debug
      command:
        - /busybox/cat
      tty: true
    - name: azure
      image: mcr.microsoft.com/azure-cli:2.61.0
      command:
        - cat
      tty: true
'''
    }
  }

  options {
    skipDefaultCheckout()
  }

  parameters {
    string(name: 'APP_DOMAIN', defaultValue: 'example.com', description: 'Base DNS zone, for example example.com')
    string(name: 'APP_NAMESPACE', defaultValue: 'coin-ops', description: 'AKS namespace for the release')
    string(name: 'INGRESS_TLS_SECRET_NAME', defaultValue: 'coin-ops-tls', description: 'TLS secret name used by the ingress')
    string(name: 'INGRESS_CONTROLLER_SERVICE_NAMESPACE', defaultValue: 'traefik', description: 'Namespace of the Traefik LoadBalancer service if ingress status is empty')
    string(name: 'INGRESS_CONTROLLER_SERVICE_NAME', defaultValue: 'traefik', description: 'Name of the Traefik LoadBalancer service if ingress status is empty')
  }

  environment {
    APP_NAME = 'coin-ops'
    APP_NAMESPACE = "${params.APP_NAMESPACE}"
    CHART_DIR = 'helm/coin-ops'
    IMAGE_NAME = 'coin-ops'
    APP_HOST = "coin-ops.${params.APP_DOMAIN}"
    INGRESS_CONTROLLER_SERVICE_NAMESPACE = "${params.INGRESS_CONTROLLER_SERVICE_NAMESPACE}"
    INGRESS_CONTROLLER_SERVICE_NAME = "${params.INGRESS_CONTROLLER_SERVICE_NAME}"
  }

  stages {
    stage('Checkout source code') {
      steps {
        script {
          def scmVars = checkout scm
          if (scmVars?.GIT_COMMIT) {
            env.GIT_COMMIT = scmVars.GIT_COMMIT
          }
        }
      }
    }

    stage('Prepare build metadata') {
      steps {
        script {
          def fullSha = env.GIT_COMMIT ?: 'manual'
          def shortSha = fullSha.length() >= 7 ? fullSha.take(7) : fullSha
          def imageTag = "${env.BUILD_NUMBER}-${shortSha}"
          def imageTagSha = fullSha.length() >= 12 ? fullSha.take(12) : fullSha
          def imageTagBuild = "build-${env.BUILD_NUMBER}"

          writeFile file: '.build.env', text: """IMAGE_TAG=${imageTag}
IMAGE_TAG_SHA=${imageTagSha}
IMAGE_TAG_BUILD=${imageTagBuild}
"""
        }
      }
    }

    stage('Run basic validation') {
      steps {
        container('node') {
          sh '''
          set -eu
          . ./.build.env
          cd ui-react
          npm ci
          npm run lint
          npm run test:run
          '''
        }
      }
    }

    stage('Resolve ACR login server') {
      steps {
        container('azure') {
          withCredentials([
            string(credentialsId: 'AZURE_CLIENT_ID', variable: 'AZURE_CLIENT_ID'),
            string(credentialsId: 'AZURE_CLIENT_SECRET', variable: 'AZURE_CLIENT_SECRET'),
            string(credentialsId: 'AZURE_TENANT_ID', variable: 'AZURE_TENANT_ID'),
            string(credentialsId: 'AZURE_SUBSCRIPTION_ID', variable: 'AZURE_SUBSCRIPTION_ID'),
            string(credentialsId: 'ACR_NAME', variable: 'ACR_NAME')
          ]) {
            sh '''
            set -eu
            az login --service-principal \
              --username "${AZURE_CLIENT_ID}" \
              --password "${AZURE_CLIENT_SECRET}" \
              --tenant "${AZURE_TENANT_ID}" >/dev/null
            az account set --subscription "${AZURE_SUBSCRIPTION_ID}"

            ACR_LOGIN_SERVER="$(az acr show --name "${ACR_NAME}" --query loginServer -o tsv)"
            echo "ACR_LOGIN_SERVER=${ACR_LOGIN_SERVER}" > .acr.env
            '''
          }
        }
      }
    }

    stage('Build and push image to ACR') {
      steps {
        container('kaniko') {
          withCredentials([usernamePassword(credentialsId: 'acr-push', usernameVariable: 'ACR_USER', passwordVariable: 'ACR_PASS')]) {
            sh '''
            set -eu
            . ./.build.env
            . ./.acr.env

            mkdir -p /kaniko/.docker
            cat > /kaniko/.docker/config.json <<EOF
{"auths":{"${ACR_LOGIN_SERVER}":{"username":"${ACR_USER}","password":"${ACR_PASS}"}}}
EOF

            /kaniko/executor \
              --context "${WORKSPACE}" \
              --dockerfile "${WORKSPACE}/Dockerfile" \
              --destination "${ACR_LOGIN_SERVER}/${IMAGE_NAME}:${IMAGE_TAG}" \
              --destination "${ACR_LOGIN_SERVER}/${IMAGE_NAME}:${IMAGE_TAG_SHA}" \
              --destination "${ACR_LOGIN_SERVER}/${IMAGE_NAME}:${IMAGE_TAG_BUILD}" \
              --cache=true

            /kaniko/executor \
              --context "${WORKSPACE}/proxy" \
              --dockerfile "${WORKSPACE}/proxy/Dockerfile" \
              --destination "${ACR_LOGIN_SERVER}/coin-ops-proxy:${IMAGE_TAG}" \
              --destination "${ACR_LOGIN_SERVER}/coin-ops-proxy:${IMAGE_TAG_SHA}" \
              --destination "${ACR_LOGIN_SERVER}/coin-ops-proxy:${IMAGE_TAG_BUILD}" \
              --cache=true

            /kaniko/executor \
              --context "${WORKSPACE}/history" \
              --dockerfile "${WORKSPACE}/history/Dockerfile.api" \
              --destination "${ACR_LOGIN_SERVER}/coin-ops-history-api:${IMAGE_TAG}" \
              --destination "${ACR_LOGIN_SERVER}/coin-ops-history-api:${IMAGE_TAG_SHA}" \
              --destination "${ACR_LOGIN_SERVER}/coin-ops-history-api:${IMAGE_TAG_BUILD}" \
              --cache=true

            /kaniko/executor \
              --context "${WORKSPACE}/history" \
              --dockerfile "${WORKSPACE}/history/Dockerfile.consumer" \
              --destination "${ACR_LOGIN_SERVER}/coin-ops-history-consumer:${IMAGE_TAG}" \
              --destination "${ACR_LOGIN_SERVER}/coin-ops-history-consumer:${IMAGE_TAG_SHA}" \
              --destination "${ACR_LOGIN_SERVER}/coin-ops-history-consumer:${IMAGE_TAG_BUILD}" \
              --cache=true
            '''
          }
        }
      }
    }

    stage('Deploy application to AKS using Helm') {
      steps {
        container('azure') {
          withCredentials([file(credentialsId: 'KUBECONFIG', variable: 'KUBECONFIG')]) {
            sh '''
            set -eu
            . ./.acr.env
            . ./.build.env

            if ! command -v kubectl >/dev/null 2>&1; then
              az aks install-cli --install-location /usr/local/bin/kubectl
            fi
            if ! command -v curl >/dev/null 2>&1; then
              if command -v apk >/dev/null 2>&1; then
                apk add --no-cache curl tar gzip
              elif command -v apt-get >/dev/null 2>&1; then
                apt-get update
                apt-get install -y curl tar gzip
              elif command -v microdnf >/dev/null 2>&1; then
                microdnf install -y curl tar gzip
              elif command -v dnf >/dev/null 2>&1; then
                dnf install -y curl tar gzip
              elif command -v tdnf >/dev/null 2>&1; then
                tdnf install -y curl tar gzip
              else
                echo "No supported package manager found to install curl"
                exit 1
              fi
            fi
            if ! command -v helm >/dev/null 2>&1; then
              HELM_VERSION="v3.16.1"
              curl -fsSL "https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz" -o /tmp/helm.tgz
              tar -xzf /tmp/helm.tgz -C /tmp
              install /tmp/linux-amd64/helm /usr/local/bin/helm
            fi

            helm dependency update "${CHART_DIR}" >/dev/null 2>&1 || true

            helm upgrade --install "${APP_NAME}" "${CHART_DIR}" \
              --namespace "${APP_NAMESPACE}" \
              --create-namespace \
              -f "${CHART_DIR}/values.yaml" \
              -f "${CHART_DIR}/values-prod.yaml" \
              --set-string image.repository="${ACR_LOGIN_SERVER}/${IMAGE_NAME}" \
              --set-string image.tag="${IMAGE_TAG}" \
              --set-string proxy.image.repository="${ACR_LOGIN_SERVER}/coin-ops-proxy" \
              --set-string proxy.image.tag="${IMAGE_TAG}" \
              --set-string historyApi.image.repository="${ACR_LOGIN_SERVER}/coin-ops-history-api" \
              --set-string historyApi.image.tag="${IMAGE_TAG}" \
              --set-string historyConsumer.image.repository="${ACR_LOGIN_SERVER}/coin-ops-history-consumer" \
              --set-string historyConsumer.image.tag="${IMAGE_TAG}" \
              --set-string ingress.host="${APP_HOST}" \
              --set-string ingress.tls.secretName="${INGRESS_TLS_SECRET_NAME}" \
              --atomic \
              --wait \
              --timeout 10m

            kubectl --kubeconfig "${KUBECONFIG}" rollout status deployment/"${APP_NAME}" -n "${APP_NAMESPACE}" --timeout=300s
            '''
          }
        }
      }
    }

    stage('Obtain application external endpoint') {
      steps {
        container('azure') {
          withCredentials([file(credentialsId: 'KUBECONFIG', variable: 'KUBECONFIG')]) {
            sh '''
            set -eu

            EXTERNAL_IP=""
            for _ in $(seq 1 30); do
              EXTERNAL_IP="$(kubectl --kubeconfig "${KUBECONFIG}" get ingress "${APP_NAME}" -n "${APP_NAMESPACE}" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"
              if [ -n "${EXTERNAL_IP}" ]; then
                break
              fi
              EXTERNAL_IP="$(kubectl --kubeconfig "${KUBECONFIG}" get svc "${INGRESS_CONTROLLER_SERVICE_NAME}" -n "${INGRESS_CONTROLLER_SERVICE_NAMESPACE}" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"
              if [ -n "${EXTERNAL_IP}" ]; then
                break
              fi
              sleep 10
            done

            if [ -z "${EXTERNAL_IP}" ]; then
              echo "Failed to resolve ingress LoadBalancer IP."
              exit 1
            fi

            echo "EXTERNAL_IP=${EXTERNAL_IP}" > .deploy.env
            echo "Resolved endpoint IP: ${EXTERNAL_IP}"
            '''
          }
        }
      }
    }

    stage('Create or update Cloudflare DNS record') {
      steps {
        container('azure') {
          withCredentials([
            string(credentialsId: 'CLOUDFLARE_API_TOKEN', variable: 'CLOUDFLARE_API_TOKEN'),
            string(credentialsId: 'CLOUDFLARE_ZONE_ID', variable: 'CLOUDFLARE_ZONE_ID')
          ]) {
            sh '''
            set -eu
            . ./.deploy.env
            chmod +x scripts/cloudflare-dns.sh
            CLOUDFLARE_API_TOKEN="${CLOUDFLARE_API_TOKEN}" \
            CLOUDFLARE_ZONE_ID="${CLOUDFLARE_ZONE_ID}" \
            CLOUDFLARE_PROXIED="false" \
            scripts/cloudflare-dns.sh upsert "${APP_HOST}" "${EXTERNAL_IP}"
            '''
          }
        }
      }
    }

    stage('Verify application availability') {
      steps {
        container('azure') {
          sh '''
          set -eu
          . ./.deploy.env

          echo "Verifying origin directly via ingress IP ${EXTERNAL_IP}."
          curl --fail --silent --show-error \
            --resolve "${APP_HOST}:443:${EXTERNAL_IP}" \
            --retry 12 \
            --retry-delay 10 \
            --retry-all-errors \
            "https://${APP_HOST}"

          echo "Verifying public Cloudflare endpoint."
          curl --fail --silent --show-error \
            --retry 60 \
            --retry-delay 10 \
            --retry-all-errors \
            "https://${APP_HOST}"

          echo "Verifying proxied API routes."
          curl --fail --silent --show-error \
            --retry 30 \
            --retry-delay 10 \
            --retry-all-errors \
            "https://${APP_HOST}/api/health"

          curl --fail --silent --show-error \
            --retry 30 \
            --retry-delay 10 \
            --retry-all-errors \
            "https://${APP_HOST}/history-api/health"
          '''
        }
      }
    }
  }

  post {
    always {
      script {
        if (env.WORKSPACE?.trim()) {
          sh 'rm -f .acr.env .build.env .deploy.env || true'
        }
      }
    }
  }
}
