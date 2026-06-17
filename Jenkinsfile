pipeline {
  agent any

  options {
    timestamps()
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
        checkout scm
      }
    }

    stage('Build Docker image') {
      steps {
        sh '''
          set -euo pipefail
          SHORT_SHA="$(git rev-parse --short=7 HEAD)"
          FULL_SHA="$(git rev-parse --short=12 HEAD)"
          IMAGE_TAG="${BUILD_NUMBER}-${SHORT_SHA}"
          IMAGE_TAG_SHA="${FULL_SHA}"
          IMAGE_TAG_BUILD="build-${BUILD_NUMBER}"

          cat > .build.env <<EOF
IMAGE_TAG=${IMAGE_TAG}
IMAGE_TAG_SHA=${IMAGE_TAG_SHA}
IMAGE_TAG_BUILD=${IMAGE_TAG_BUILD}
EOF

          docker build -t "${IMAGE_NAME}:${IMAGE_TAG}" .
          docker tag "${IMAGE_NAME}:${IMAGE_TAG}" "${IMAGE_NAME}:${IMAGE_TAG_SHA}"
          docker tag "${IMAGE_NAME}:${IMAGE_TAG}" "${IMAGE_NAME}:${IMAGE_TAG_BUILD}"
        '''
      }
    }

    stage('Run basic validation') {
      steps {
        sh '''
          set -euo pipefail
          . ./.build.env
          docker image inspect "${IMAGE_NAME}:${IMAGE_TAG}" >/dev/null
          docker run --rm -u "$(id -u):$(id -g)" -v "$PWD:/workspace" -w /workspace/ui-react node:22-bookworm-slim bash -lc '
            npm ci
            npm run lint
            npm run test:run
          '
        '''
      }
    }

    stage('Login to ACR and push image') {
      steps {
        withCredentials([
          string(credentialsId: 'AZURE_CLIENT_ID', variable: 'AZURE_CLIENT_ID'),
          string(credentialsId: 'AZURE_CLIENT_SECRET', variable: 'AZURE_CLIENT_SECRET'),
          string(credentialsId: 'AZURE_TENANT_ID', variable: 'AZURE_TENANT_ID'),
          string(credentialsId: 'AZURE_SUBSCRIPTION_ID', variable: 'AZURE_SUBSCRIPTION_ID'),
          string(credentialsId: 'ACR_NAME', variable: 'ACR_NAME')
        ]) {
          sh '''
            set -euo pipefail
            . ./.build.env
            az login --service-principal \
              --username "${AZURE_CLIENT_ID}" \
              --password "${AZURE_CLIENT_SECRET}" \
              --tenant "${AZURE_TENANT_ID}" >/dev/null
            az account set --subscription "${AZURE_SUBSCRIPTION_ID}"
            az acr login --name "${ACR_NAME}"

            ACR_LOGIN_SERVER="$(az acr show --name "${ACR_NAME}" --query loginServer -o tsv)"
            echo "ACR_LOGIN_SERVER=${ACR_LOGIN_SERVER}" > .acr.env

            docker tag "${IMAGE_NAME}:${IMAGE_TAG}" "${ACR_LOGIN_SERVER}/${IMAGE_NAME}:${IMAGE_TAG}"
            docker tag "${IMAGE_NAME}:${IMAGE_TAG}" "${ACR_LOGIN_SERVER}/${IMAGE_NAME}:${IMAGE_TAG_SHA}"
            docker tag "${IMAGE_NAME}:${IMAGE_TAG}" "${ACR_LOGIN_SERVER}/${IMAGE_NAME}:${IMAGE_TAG_BUILD}"

            docker push "${ACR_LOGIN_SERVER}/${IMAGE_NAME}:${IMAGE_TAG}"
            docker push "${ACR_LOGIN_SERVER}/${IMAGE_NAME}:${IMAGE_TAG_SHA}"
            docker push "${ACR_LOGIN_SERVER}/${IMAGE_NAME}:${IMAGE_TAG_BUILD}"
          '''
        }
      }
    }

    stage('Deploy application to AKS using Helm') {
      steps {
        withCredentials([file(credentialsId: 'KUBECONFIG', variable: 'KUBECONFIG')]) {
          sh '''
            set -euo pipefail
            . ./.acr.env
            . ./.build.env

            helm dependency update "${CHART_DIR}" >/dev/null 2>&1 || true

            helm upgrade --install "${APP_NAME}" "${CHART_DIR}" \
              --namespace "${APP_NAMESPACE}" \
              --create-namespace \
              -f "${CHART_DIR}/values.yaml" \
              -f "${CHART_DIR}/values-prod.yaml" \
              --set-string image.repository="${ACR_LOGIN_SERVER}/${IMAGE_NAME}" \
              --set-string image.tag="${IMAGE_TAG}" \
              --set-string ingress.host="${APP_HOST}" \
              --set-string ingress.tls.secretName="${INGRESS_TLS_SECRET_NAME}" \
              --wait \
              --timeout 10m

            kubectl --kubeconfig "${KUBECONFIG}" rollout status deployment/"${APP_NAME}" -n "${APP_NAMESPACE}" --timeout=300s
          '''
        }
      }
    }

    stage('Obtain application external endpoint') {
      steps {
        withCredentials([file(credentialsId: 'KUBECONFIG', variable: 'KUBECONFIG')]) {
          sh '''
            set -euo pipefail

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

    stage('Create or update Cloudflare DNS record') {
      steps {
        withCredentials([
          string(credentialsId: 'CLOUDFLARE_API_TOKEN', variable: 'CLOUDFLARE_API_TOKEN'),
          string(credentialsId: 'CLOUDFLARE_ZONE_ID', variable: 'CLOUDFLARE_ZONE_ID')
        ]) {
          sh '''
            set -euo pipefail
            . ./.deploy.env
            chmod +x scripts/cloudflare-dns.sh
            CLOUDFLARE_API_TOKEN="${CLOUDFLARE_API_TOKEN}" \
            CLOUDFLARE_ZONE_ID="${CLOUDFLARE_ZONE_ID}" \
            scripts/cloudflare-dns.sh upsert "${APP_HOST}" "${EXTERNAL_IP}"
          '''
        }
      }
    }

    stage('Verify application availability') {
      steps {
        sh '''
          set -euo pipefail
          curl --fail --silent --show-error \
            --retry 12 \
            --retry-delay 10 \
            --retry-all-errors \
            "https://${APP_HOST}"
        '''
      }
    }
  }

  post {
    failure {
      withCredentials([file(credentialsId: 'KUBECONFIG', variable: 'KUBECONFIG')]) {
        sh '''
          set +e
          PREVIOUS_DEPLOYED_REVISION="$(
            helm history "${APP_NAME}" -n "${APP_NAMESPACE}" -o json 2>/dev/null | python3 -c '
import json, sys
history = json.load(sys.stdin) if not sys.stdin.isatty() else []
deployed = [item["revision"] for item in history if item.get("status") == "deployed"]
print(deployed[-1] if deployed else "")
'
          )"

          if [ -n "${PREVIOUS_DEPLOYED_REVISION}" ]; then
            echo "Rolling back ${APP_NAME} to revision ${PREVIOUS_DEPLOYED_REVISION}"
            helm rollback "${APP_NAME}" "${PREVIOUS_DEPLOYED_REVISION}" -n "${APP_NAMESPACE}" --wait --timeout 10m
            kubectl --kubeconfig "${KUBECONFIG}" rollout status deployment/"${APP_NAME}" -n "${APP_NAMESPACE}" --timeout=300s
          else
            echo "No previous deployed Helm revision found. Skipping rollback."
          fi
        '''
      }
    }
    always {
      sh 'rm -f .acr.env .build.env .deploy.env'
    }
  }
}
