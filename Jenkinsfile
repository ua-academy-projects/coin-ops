pipeline {
    agent {
        kubernetes {
            yaml """
apiVersion: v1
kind: Pod
spec:
  serviceAccountName: jenkins-deployer
  containers:
    - name: tools
      image: alpine/k8s:1.30.4
      command: [sleep]
      args: [infinity]
"""
        }
    }

    environment {
      SHA = "${env.GIT_COMMIT[0..6]}"
    }

    stages {
      stage('Checkout') {
        steps {
          checkout scm
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
                --from-literal=DATABASE_URL='postgres://postgres:postgres@postgres.coinops-data.svc.cluster.local:5432/currency_rates_tracker?sslmode=disable' \
                --from-literal=REDIS_URL='redis://redis.coinops-data.svc.cluster.local:6379' \
                --from-literal=RABBITMQ_URL='amqp://admin:admin@rabbitmq.coinops-data.svc.cluster.local:5672/' \
                --from-literal=RUNTIME_BACKEND=external \
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