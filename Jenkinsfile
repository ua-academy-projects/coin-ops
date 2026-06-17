pipeline {
    agent {
        kubernetes {
            yaml """
apiVersion: v1
kind: Pod
spec:
  serviceAccountName: jenkins-deployer
  containers:
    - name: kaniko-proxy
      image: gcr.io/kaniko-project/executor:v1.23.2-debug
      command: [sleep]
      args: [infinity]
      volumeMounts:
        - name: docker-config
          mountPath: /kaniko/.docker
    - name: kaniko-api
      image: gcr.io/kaniko-project/executor:v1.23.2-debug
      command: [sleep]
      args: [infinity]
      volumeMounts:
        - name: docker-config
          mountPath: /kaniko/.docker
    - name: kaniko-consumer
      image: gcr.io/kaniko-project/executor:v1.23.2-debug
      command: [sleep]
      args: [infinity]
      volumeMounts:
        - name: docker-config
          mountPath: /kaniko/.docker
    - name: kaniko-ui
      image: gcr.io/kaniko-project/executor:v1.23.2-debug
      command: [sleep]
      args: [infinity]
      volumeMounts:
        - name: docker-config
          mountPath: /kaniko/.docker
    - name: tools
      image: alpine/k8s:1.30.4
      command: [sleep]
      args: [infinity]
  volumes:
    - name: docker-config
      secret:
        secretName: ghcr-dockerconfigjson
        items:
        - key: .dockerconfigjson
          path: config.json
"""
        }
    }

    environment {
      REGISTRY = "rkurdupel"
      SHA = "${env.GIT_COMMIT[0..6]}"
      AKS_CLUSTER = "coinops-aks"
      RESOURCE_GROUP = "coinops-aks-rg"
    }

    stages {
      stage('Checkout') {
        steps {
          checkout scm
        }
      }

      stage('Build proxy') {
        steps {
          container('kaniko-proxy') {
            sh """
                /kaniko/executor \
                  --context=dir://\$WORKSPACE/proxy \
                  --dockerfile=\$WORKSPACE/proxy/Dockerfile \
                  --destination=${REGISTRY}/coin-ops-proxy:${SHA} \
                  --destination=${REGISTRY}/coin-ops-proxy:latest
            """
          }
        }
      }

      stage('Build history-api') {
        steps {
          container('kaniko-api') {
            sh """
                /kaniko/executor \
                  --context=dir://\$WORKSPACE/history \
                  --dockerfile=\$WORKSPACE/history/Dockerfile.api \
                  --destination=${REGISTRY}/coin-ops-history-api:${SHA} \
                  --destination=${REGISTRY}/coin-ops-history-api:latest
            """
          }
        }
      }

      stage('Build history-consumer') {
        steps {
          container('kaniko-consumer') {
            sh """
                /kaniko/executor \
                  --context=dir://\$WORKSPACE/history \
                  --dockerfile=\$WORKSPACE/history/Dockerfile.consumer \
                  --destination=${REGISTRY}/coin-ops-history-consumer:${SHA} \
                  --destination=${REGISTRY}/coin-ops-history-consumer:latest
            """
          }
        }
      }

      stage('Build ui') {
        steps {
          container('kaniko-ui') {
            sh """
                /kaniko/executor \
                  --context=dir://\$WORKSPACE/ui-react \
                  --dockerfile=\$WORKSPACE/ui-react/Dockerfile \
                  --destination=${REGISTRY}/coin-ops-ui:${SHA} \
                  --destination=${REGISTRY}/coin-ops-ui:latest
            """
          }
        }
      }

      stage('Deploy Bitnami dependencies') {
        steps {
          container('tools') {
            sh '''
              helm repo add bitnami https://charts.bitnami.com/bitnami
              helm repo update

              helm upgrade --install postgres bitnami/postgresql \
                --namespace coinops-data \
                --set auth.username=postgres \
                --set auth.password=postgres \
                --set auth.database=currency_rates_tracker \
                --set primary.persistence.enabled=false \
                --wait --timeout 5m
              helm upgrade --install redis bitnami/redis \
                --namespace coinops-data \
                --set auth.enabled=false \
                --set master.persistence.enabled=false \
                --set replica.replicaCount=0 \
                --wait --timeout 5m

              helm upgrade --install rabbitmq bitnami/rabbitmq \
                --namespace coinops-data \
                --set auth.username=admin \
                --set auth.password=admin \
                --set persistence.enabled=false \
                --wait --timeout 5m
            '''
          }
        }
      }

      stage('Deploy coinops app') {
        steps {
          container('tools') {
            sh '''
              helm upgrade --install coinops ./charts/coinops \
                --namespace coinops-app \
                --set global.imageTag=${SHA} \
                --wait --timeout 5m
            '''
          }
        }
      }

      stage('Verify rollout') {
        steps {
          container('tools') {
            sh '''
              kubectl -n coinops-app rollout status deploy/proxy --timeout=180s
              kubectl -n coinops-app rollout status deploy/history-api --timeout=180s
              kubectl -n coinops-app rollout status deploy/history-consumer --timeout=180s
              kubectl -n coinops-app rollout status deploy/ui --timeout=180s
            '''
          }
        }
      }
    }

    post {
      success {
        echo "Pipeline succeeded. Images pushed and deployed to AKS."
      }
      failure {
        echo "Pipeline FAILED for commit ${env.GIT_COMMIT?.take(7)}."
      }
    }
}