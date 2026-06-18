pipeline {
  agent {
    kubernetes {
      defaultContainer 'helm'
      yaml '''
apiVersion: v1
kind: Pod
spec:
  serviceAccountName: jenkins-deployer
  containers:
    - name: azure
      image: mcr.microsoft.com/azure-cli:2.76.0
      command:
        - cat
      tty: true
    - name: helm
      image: alpine/helm:3.15.4
      command:
        - cat
      tty: true
    - name: kubectl
      image: bitnami/kubectl:1.34
      command:
        - cat
      tty: true
'''
    }
  }

  environment {
    CONFIG_FILE = 'configs/aks.json'
    RELEASE_NAME = 'coin-ops'
    CHART_DIR = 'charts/coin-ops'
    VALUES_FILE = 'charts/coin-ops/values-aks.yaml'
    APP_NAMESPACE = 'coin-ops-app'
    WORKERS_NAMESPACE = 'coin-ops-workers'
    DATA_NAMESPACE = 'coin-ops-data'
    APP_SECRET_NAME = 'coin-ops-secret'
    PULL_SECRET_NAME = 'ghcr-pull-secret'
  }

  stages {
    stage('Check Tools') {
      steps {
        container('azure') {
          sh 'az version'
        }
        container('helm') {
          sh 'helm version'
        }
        container('kubectl') {
          sh 'kubectl version --client=true'
        }
      }
    }

    stage('Read Config') {
      steps {
        script {
          def config = readJSON file: env.CONFIG_FILE

          env.IMAGE_REGISTRY = config.deploy.image_registry
          env.IMAGE_PULL_SERVER = config.deploy.image_registry.tokenize('/')[0]
          env.IMAGE_TAG = params.IMAGE_TAG ?: config.deploy.image_tag
          env.RUNTIME_BACKEND = config.deploy.runtime_backend
          env.POSTGRES_HOST = "${config.sql.instance.name}.postgres.database.azure.com"
          env.POSTGRES_DB = config.sql.database.name
          env.POSTGRES_USER = config.sql.user.name
          env.DB_PASSWORD_SECRET = config.secrets.db_password.secret_id
          env.RABBITMQ_PASSWORD_SECRET = config.secrets.rabbitmq_password.secret_id
          env.GHCR_USERNAME_SECRET = config.secrets.ghcr_username.secret_id
          env.GHCR_TOKEN_SECRET = config.secrets.ghcr_token.secret_id
        }
      }
    }

    stage('Fetch Secrets') {
      steps {
        container('azure') {
          withCredentials([
            string(credentialsId: 'azure-client-id', variable: 'AZURE_CLIENT_ID'),
            string(credentialsId: 'azure-client-secret', variable: 'AZURE_CLIENT_SECRET'),
            string(credentialsId: 'azure-tenant-id', variable: 'AZURE_TENANT_ID')
          ]) {
            sh '''
              set -eu
              az login \
                --service-principal \
                --username "$AZURE_CLIENT_ID" \
                --password "$AZURE_CLIENT_SECRET" \
                --tenant "$AZURE_TENANT_ID" \
                --output none
            '''
            script {
              env.DB_PASSWORD = sh(
                script: "az keyvault secret show --vault-name \"$AZ_KEYVAULT_NAME\" --name \"$DB_PASSWORD_SECRET\" --query value -o tsv",
                returnStdout: true
              ).trim()
              env.RABBITMQ_PASSWORD = sh(
                script: "az keyvault secret show --vault-name \"$AZ_KEYVAULT_NAME\" --name \"$RABBITMQ_PASSWORD_SECRET\" --query value -o tsv",
                returnStdout: true
              ).trim()
              env.GHCR_USERNAME = sh(
                script: "az keyvault secret show --vault-name \"$AZ_KEYVAULT_NAME\" --name \"$GHCR_USERNAME_SECRET\" --query value -o tsv",
                returnStdout: true
              ).trim()
              env.GHCR_TOKEN = sh(
                script: "az keyvault secret show --vault-name \"$AZ_KEYVAULT_NAME\" --name \"$GHCR_TOKEN_SECRET\" --query value -o tsv",
                returnStdout: true
              ).trim()
            }
          }
        }
      }
    }

    stage('Prepare Kubernetes Secrets') {
      steps {
        container('kubectl') {
          sh '''
            set -eu

            for namespace in "$APP_NAMESPACE" "$WORKERS_NAMESPACE" "$DATA_NAMESPACE"; do
              kubectl create namespace "$namespace" --dry-run=client -o yaml | kubectl apply -f -

              kubectl -n "$namespace" create secret docker-registry "$PULL_SECRET_NAME" \
                --docker-server="$IMAGE_PULL_SERVER" \
                --docker-username="$GHCR_USERNAME" \
                --docker-password="$GHCR_TOKEN" \
                --dry-run=client \
                -o yaml | kubectl apply -f -

              kubectl -n "$namespace" create secret generic "$APP_SECRET_NAME" \
                --from-literal=POSTGRES_USER="$POSTGRES_USER" \
                --from-literal=POSTGRES_PASSWORD="$DB_PASSWORD" \
                --from-literal=POSTGRES_DB="$POSTGRES_DB" \
                --from-literal=DATABASE_URL="postgresql://$POSTGRES_USER:$DB_PASSWORD@$POSTGRES_HOST:5432/$POSTGRES_DB?sslmode=require" \
                --from-literal=RABBITMQ_DEFAULT_USER="cognitor" \
                --from-literal=RABBITMQ_DEFAULT_PASS="$RABBITMQ_PASSWORD" \
                --from-literal=RABBITMQ_URL="amqp://cognitor:$RABBITMQ_PASSWORD@rabbitmq.$DATA_NAMESPACE.svc.cluster.local:5672/" \
                --from-literal=REDIS_URL="redis://redis.$DATA_NAMESPACE.svc.cluster.local:6379/0" \
                --dry-run=client \
                -o yaml | kubectl apply -f -
            done
          '''
        }
      }
    }

    stage('Deploy Helm Chart') {
      steps {
        container('helm') {
          sh '''
            set -eu

            helm upgrade --install "$RELEASE_NAME" "$CHART_DIR" \
              --namespace "$APP_NAMESPACE" \
              --values "$VALUES_FILE" \
              --set-string config.data.RUNTIME_BACKEND="$RUNTIME_BACKEND" \
              --set-string proxy.image.repository="$IMAGE_REGISTRY/coin-ops-proxy" \
              --set-string proxy.image.tag="$IMAGE_TAG" \
              --set-string historyApi.image.repository="$IMAGE_REGISTRY/coin-ops-history-api" \
              --set-string historyApi.image.tag="$IMAGE_TAG" \
              --set-string historyConsumer.image.repository="$IMAGE_REGISTRY/coin-ops-history-consumer" \
              --set-string historyConsumer.image.tag="$IMAGE_TAG" \
              --set-string ui.image.repository="$IMAGE_REGISTRY/coin-ops-ui" \
              --set-string ui.image.tag="$IMAGE_TAG" \
              --wait \
              --timeout 10m
          '''
        }
      }
    }

    stage('Verify') {
      steps {
        container('kubectl') {
          sh '''
            set -eu
            kubectl -n "$APP_NAMESPACE" rollout status deployment/proxy --timeout=3m
            kubectl -n "$APP_NAMESPACE" rollout status deployment/history-api --timeout=3m
            kubectl -n "$APP_NAMESPACE" rollout status deployment/ui --timeout=3m
            kubectl -n "$WORKERS_NAMESPACE" rollout status deployment/history-consumer --timeout=3m
          '''
        }
      }
    }
  }

  parameters {
    string(name: 'IMAGE_TAG', defaultValue: '', description: 'Optional image tag override. Empty uses configs/aks.json deploy.image_tag.')
  }
}
