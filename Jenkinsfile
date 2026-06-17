pipeline {
    agent {
        kubernetes {
            yaml """
apiVersion: v1
kind: Pod
spec:
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
      image: alpine/helm:3.14.0
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
      NAMESPACE = "coinops"
    }

    stages {
      stage('Checkout') {
        steps {
          checkout scm
        }
      }

      stage('Build proxy') {
        steps {
          container('kaniko') {
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
          container('kaniko') {
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
          container('kaniko') {
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
          container('kaniko') {
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

      stage('Terraform Plan') {
        steps {
          container('tools') {
            dir('terraform') {
              sh 'terraform init'
              sh 'terraform plan -out=tfplan'
            }
          }
        }
      }

      stage('Approval') {
        steps {
          input message: 'Terraform plan completed. Proceed with apply?',
            ok: 'Proceed'
        }
      }

      stage('Terraform Apply') {
        steps {
          container('tools') {
            dir('terraform') {
              sh 'terraform apply -auto-approve tfplan'
            }
          }
        }
      }
    }
}