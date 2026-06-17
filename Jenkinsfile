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

      stage('Deploy data services') {
        steps {
          container('tools') {
            sh '''
              # Postgres
              kubectl -n coinops-data create deployment postgres \
                --image=postgres:16-alpine \
                --dry-run=client -o yaml | kubectl apply -f -
              
              kubectl -n coinops-data set env deployment/postgres \
                POSTGRES_USER=postgres \
                POSTGRES_PASSWORD=postgres \
                POSTGRES_DB=currency_rates_tracker
              
              kubectl -n coinops-data expose deployment postgres \
                --port=5432 --target-port=5432 \
                --dry-run=client -o yaml | kubectl apply -f -
              
              # Redis
              kubectl -n coinops-data create deployment redis \
                --image=redis:7-alpine \
                --dry-run=client -o yaml | kubectl apply -f -
              
              kubectl -n coinops-data expose deployment redis \
                --port=6379 --target-port=6379 \
                --dry-run=client -o yaml | kubectl apply -f -
              
              # RabbitMQ
              kubectl -n coinops-data create deployment rabbitmq \
                --image=rabbitmq:3-management-alpine \
                --dry-run=client -o yaml | kubectl apply -f -
              
              kubectl -n coinops-data set env deployment/rabbitmq \
                RABBITMQ_DEFAULT_USER=admin \
                RABBITMQ_DEFAULT_PASS=admin
              
              kubectl -n coinops-data expose deployment rabbitmq \
                --port=5672 --target-port=5672 \
                --dry-run=client -o yaml | kubectl apply -f -
              
              kubectl -n coinops-data rollout status deploy/postgres --timeout=120s
              kubectl -n coinops-data rollout status deploy/redis --timeout=120s
              kubectl -n coinops-data rollout status deploy/rabbitmq --timeout=120s

              kubectl create secret generic coinops-secrets \
                --namespace coinops-app \
                --from-literal=DB_NAME=currency_rates_tracker \
                --from-literal=DB_USER=postgres \
                --from-literal=DB_PASSWORD=postgres \
                --from-literal=DB_HOST=postgres.coinops-data.svc.cluster.local \
                --from-literal=DB_PORT=5432 \
                --from-literal=REDIS_HOST=redis.coinops-data.svc.cluster.local \
                --from-literal=REDIS_PORT=6379 \
                --from-literal=RABBITMQ_HOST=rabbitmq.coinops-data.svc.cluster.local \
                --from-literal=RABBITMQ_PORT=5672 \
                --from-literal=RABBITMQ_USER=admin \
                --from-literal=RABBITMQ_PASSWORD=admin \
                --dry-run=client -o yaml | kubectl apply -f -
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