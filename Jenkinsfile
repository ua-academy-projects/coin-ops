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
    - name: terraform
      image: hashicorp/terraform:1.9.8
      command: [sleep]
      args: [infinity]
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

      TF_VAR_db_name = "currency_rates_tracker"
      TF_VAR_db_user = "postgres"
      TF_VAR_db_password = "postgres"
      TF_VAR_domain_name = "coin-ops.pp.ua"

			AWS_DEFAULT_REGION = "eu-central-1"
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
      // stage('Terraform Plan') {
      //   steps {
      //     container('terraform') {
      //       withCredentials([
      //         file(credentialsId: 'gcp-sa-key', variable: 'GOOGLE_APPLICATION_CREDENTIALS'),
			// 				file(credentialsId: 'sshkey', variable: 'SSH_PUBLIC_KEY_PATH'),
      //         string(credentialsId: 'azure-client-id', variable: 'ARM_CLIENT_ID'),
      //         string(credentialsId: 'azure-client-secret', variable: 'ARM_CLIENT_SECRET'),
      //         string(credentialsId: 'azure-tenant-id', variable: 'ARM_TENANT_ID'),
      //         string(credentialsId: 'azure-subscription-id', variable: 'ARM_SUBSCRIPTION_ID'),
      //         string(credentialsId: 'cloudflare-api-token', variable: 'TF_VAR_cloudflare_api_token'),
      //         string(credentialsId: 'cloudflare-zone-id', variable: 'TF_VAR_cloudflare_zone_id'),
			// 				string(credentialsId: 'aws-access-key-id', variable: 'AWS_ACCESS_KEY_ID'),
			// 				string(credentialsId: 'aws-secret-access-key', variable: 'AWS_SECRET_ACCESS_KEY')
      //       ]) {
			// 				sh '''
			// 					cat > /tmp/id_ed25519.pub <<EOF
			// 				ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMCAv5M0/tJCzjIM2iTjeJDc4UivC7hOUH/M8RBL/iOp rkurdupel@Romans-MacBook-Pro.local
			// 				EOF	'''
      //         dir('terraform') {
      //           sh 'terraform init'
      //           sh 'terraform plan -out=tfplan'
      //         }
      //       }
      //     }
      //   }
      // }

      // stage('Approval') {
      //   steps {
      //     input message: 'Terraform plan completed. Proceed with apply?',
      //       ok: 'Proceed'
      //   }
      // }

      // stage('Terraform Apply') {
      //   steps {
      //     container('terraform') {
      //       withCredentials([
      //         file(credentialsId: 'gcp-sa-key', variable: 'GOOGLE_APPLICATION_CREDENTIALS'),
      //         string(credentialsId: 'azure-client-id', variable: 'ARM_CLIENT_ID'),
      //         string(credentialsId: 'azure-client-secret', variable: 'ARM_CLIENT_SECRET'),
      //         string(credentialsId: 'azure-tenant-id', variable: 'ARM_TENANT_ID'),
      //         string(credentialsId: 'azure-subscription-id', variable: 'ARM_SUBSCRIPTION_ID'),
      //         string(credentialsId: 'cloudflare-api-token', variable: 'TF_VAR_cloudflare_api_token'),
      //         string(credentialsId: 'cloudflare-zone-id', variable: 'TF_VAR_cloudflare_zone_id'),
			// 				string(credentialsId: 'aws-access-key-id', variable: 'AWS_ACCESS_KEY_ID'),
			// 				string(credentialsId: 'aws-secret-access-key', variable: 'AWS_SECRET_ACCESS_KEY')
      //       ]) {
			// 				sh '''
			// 					cat > /tmp/id_ed25519.pub <<EOF
			// 				ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMCAv5M0/tJCzjIM2iTjeJDc4UivC7hOUH/M8RBL/iOp rkurdupel@Romans-MacBook-Pro.local
			// 				EOF	'''
      //         dir('terraform') {
      //           sh 'terraform apply -auto-approve tfplan'
      //         }
      //       }
      //     }
       // }
     // }
    }
}